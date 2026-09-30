"""Agent 4 of the Platform Operations Copilot: Validation / Safety.

Plain Python. No language model, no tools, no network. That is the point: it
is the one stage whose behaviour must be identical on every run, including
the runs where the model upstream has been talked into something by text it
read in a tenant's name.

It checks each proposal against platform policy and either accepts it, trims
it into policy, or rejects it. Verdicts are per-intervention rather than for
the batch, because a run with four sound proposals and one out-of-policy
proposal should leave the owner with four to approve.

What it never does is approve. `requires_human_approval` is true whenever
anything survives, and there is no path through this function that sets it
false with work still to do. Approval is the owner's, in ASP.NET Core,
behind an authenticator code.
"""
from __future__ import annotations

from schemas.platform_contracts import (
    InterventionVerdict,
    PlatformActionOutput,
    PlatformAnalysisOutput,
    PlatformSafetyOutput,
    ProposedIntervention,
)

# ── Policy. Stated once, here, so it is reviewable in one place. ────────

# The interventions the owner console can actually carry out.
ALLOWED_KINDS = {"extend_term", "comp_plan", "winback_offer", "contact_owner", "no_action"}

# An extension is meant to cover a slipped payment, not to become a
# permanent discount by another name.
MAX_EXTEND_DAYS = 90

# Comps are the expensive one. The per-run ceiling is what stops a single
# confused run giving away a month of revenue.
MAX_COMP_MONTHS_CEILING = 24

# Plans a comp may name. A comp onto a plan that does not exist would fail
# at execution; better to refuse it here, where it is visible.
KNOWN_PLANS = {"starter", "grow", "pro", "prime"}

# A business doing nothing does not need a discount, it needs a call. The
# model is told this; this is the check that makes it true.
DORMANT_BOOKINGS_30D = 0

# Nothing is free to be wrong about at scale.
MAX_TOTAL_COST_MULTIPLE = 3.0


def run(
    *,
    analysis: PlatformAnalysisOutput,
    actions: PlatformActionOutput,
    activity: dict[str, dict],
    max_interventions: int,
    max_comp_months: int,
) -> PlatformSafetyOutput:
    risk_by_tenant = {t.tenant_id: t for t in analysis.at_risk}
    verdicts: list[InterventionVerdict] = []
    accepted: list[ProposedIntervention] = []
    notes: list[str] = []

    comp_ceiling = min(max_comp_months, MAX_COMP_MONTHS_CEILING)
    if max_comp_months > MAX_COMP_MONTHS_CEILING:
        notes.append(
            f"Requested comp ceiling of {max_comp_months} months trimmed to the policy maximum of "
            f"{MAX_COMP_MONTHS_CEILING}."
        )

    seen_tenants: set[str] = set()

    for proposal in actions.interventions:
        verdict = _judge(
            proposal,
            risk=risk_by_tenant.get(proposal.tenant_id),
            activity=activity.get(proposal.tenant_id) or {},
            comp_ceiling=comp_ceiling,
            already_proposed=proposal.tenant_id in seen_tenants,
        )
        verdicts.append(verdict)
        if verdict.accepted:
            seen_tenants.add(proposal.tenant_id)
            accepted.append(proposal)

    # Blast radius. Anything past the owner's ceiling is held back rather
    # than silently dropped, so the count in the trace still adds up.
    if len(accepted) > max_interventions:
        for extra in accepted[max_interventions:]:
            verdicts.append(
                InterventionVerdict(
                    tenant_id=extra.tenant_id,
                    kind=extra.kind,
                    accepted=False,
                    reason=f"Beyond this run's ceiling of {max_interventions} interventions.",
                )
            )
        notes.append(
            f"{len(accepted) - max_interventions} further proposals were held back by the run's "
            f"ceiling of {max_interventions}."
        )
        accepted = accepted[:max_interventions]

    total_cost = round(sum(i.estimated_cost for i in accepted), 2)
    total_protected = round(sum(i.protected_value for i in accepted), 2)

    # Spending more than the revenue it protects is the one arithmetic
    # mistake this whole pipeline could make that actually costs money.
    if total_protected > 0 and total_cost > total_protected * MAX_TOTAL_COST_MULTIPLE:
        return PlatformSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            accepted=[],
            verdicts=verdicts,
            rejection_reason=(
                f"Refused: the proposed interventions give up {total_cost:,.2f} to protect "
                f"{total_protected:,.2f}. Nothing has been held for approval."
            ),
            validation_notes=notes,
            total_estimated_cost=total_cost,
        )

    if not accepted:
        return PlatformSafetyOutput(
            is_allowed=True,
            requires_human_approval=False,
            accepted=[],
            verdicts=verdicts,
            rejection_reason=None,
            validation_notes=notes + ["No proposal survived validation; there is nothing to approve."],
            total_estimated_cost=0.0,
        )

    notes.append(
        f"{len(accepted)} intervention(s) held for the platform owner. Nothing has been applied: "
        "carrying any of these out requires a fresh authenticator code, which this pipeline cannot produce."
    )

    return PlatformSafetyOutput(
        is_allowed=True,
        # Always. These move money and access, and there is no route through
        # this function that lowers it.
        requires_human_approval=True,
        accepted=accepted,
        verdicts=verdicts,
        rejection_reason=None,
        validation_notes=notes,
        total_estimated_cost=total_cost,
    )


def _judge(
    proposal: ProposedIntervention,
    *,
    risk,
    activity: dict,
    comp_ceiling: int,
    already_proposed: bool,
) -> InterventionVerdict:
    kind = proposal.kind

    def refuse(reason: str) -> InterventionVerdict:
        return InterventionVerdict(tenant_id=proposal.tenant_id, kind=kind, accepted=False, reason=reason)

    if kind not in ALLOWED_KINDS:
        return refuse(f"'{kind}' is not an intervention this platform can carry out.")

    # The agent may only act on businesses the analysis actually flagged.
    # Without this, a proposal naming any tenant id at all would be executed
    # on the owner's approval - the single most dangerous thing a prompt
    # injection could achieve here.
    if risk is None:
        return refuse("This business was not in the analysed at-risk set.")

    if already_proposed:
        return refuse("A second intervention was proposed for the same business in one run.")

    if kind in ("no_action", "contact_owner"):
        # Free and reversible. Still recorded, so the owner sees what was
        # considered and consciously set aside.
        return InterventionVerdict(tenant_id=proposal.tenant_id, kind=kind, accepted=True)

    if kind == "winback_offer":
        if (risk.plan_code or "").lower() not in ("starter", ""):
            return refuse("A win-back offer is only for a business that has already lapsed to the free plan.")
        return InterventionVerdict(tenant_id=proposal.tenant_id, kind=kind, accepted=True)

    if kind == "extend_term":
        days = proposal.extend_days
        if not isinstance(days, int) or days <= 0:
            return refuse("An extension needs a positive number of days.")
        if days > MAX_EXTEND_DAYS:
            original = f"{days} days"
            proposal.extend_days = MAX_EXTEND_DAYS
            return InterventionVerdict(
                tenant_id=proposal.tenant_id,
                kind=kind,
                accepted=True,
                reason=f"Trimmed to the {MAX_EXTEND_DAYS}-day policy maximum.",
                adjusted_from=original,
            )
        return InterventionVerdict(tenant_id=proposal.tenant_id, kind=kind, accepted=True)

    # comp_plan - the expensive one, so the most checks.
    months = proposal.comp_months
    plan = (proposal.comp_plan_code or "").lower()

    if plan not in KNOWN_PLANS:
        return refuse(f"'{proposal.comp_plan_code}' is not a plan on this platform.")
    if plan == "starter":
        return refuse("Starter is already free; comping it does nothing.")
    if not isinstance(months, int) or months <= 0:
        return refuse("A comp needs a positive number of months.")

    bookings = activity.get("bookings_30d")
    if isinstance(bookings, int) and bookings <= DORMANT_BOOKINGS_30D:
        return refuse(
            "This business has no activity in the last 30 days. A free plan does not fix a business "
            "that is not using the product - propose contacting them instead."
        )

    if months > comp_ceiling:
        original = f"{months} months"
        proposal.comp_months = comp_ceiling
        return InterventionVerdict(
            tenant_id=proposal.tenant_id,
            kind=kind,
            accepted=True,
            reason=f"Trimmed to this run's ceiling of {comp_ceiling} months.",
            adjusted_from=original,
        )

    return InterventionVerdict(tenant_id=proposal.tenant_id, kind=kind, accepted=True)
