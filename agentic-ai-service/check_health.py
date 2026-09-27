"""Pre-demo health check: is the Agentic AI subsystem actually working?

    python check_health.py

Answers four questions in order, because each one only matters if the
previous passed:

    1. Is the Gemini key configured and accepted?
    2. Which models does it actually reach today? (free-tier quota is daily,
       and an exhausted model is the usual reason a demo "breaks")
    3. Is the agent service up, and is its shared secret the same one
       ASP.NET Core sends?
    4. Do all four agents really run end to end?

Step 4 is the one that matters. A working key proves nothing about the
agents, and the pipeline deliberately still works when Gemini is down (the
deterministic planner takes over) - so "it produced a schedule" is not the
same as "the language model drove it". This script separates the two and
says which happened.

It never prints the API key or the internal token, so the output is safe to
screenshot for the report.
"""
from __future__ import annotations

import os
import sys
import time

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

OK, BAD, WARN, INFO = "[ OK ]", "[FAIL]", "[WARN]", "[ .. ]"
problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)


def step(number: int, title: str) -> None:
    print(f"\n{number}. {title}\n{'-' * 62}")


# ── 1. key ──────────────────────────────────────────────────────────────
step(1, "Gemini API key")
api_key = os.getenv("GEMINI_API_KEY", "").strip()
if not api_key:
    print(f"{WARN} No GEMINI_API_KEY in .env.")
    print("       The agents still run, using the deterministic planner.")
else:
    print(f"{OK} Key found ({len(api_key)} characters, not shown).")

# ── 2. models ───────────────────────────────────────────────────────────
step(2, "Which models the key reaches today")
reachable: list[str] = []
if api_key:
    from google import genai

    client = genai.Client(api_key=api_key)
    default = os.getenv("GEMINI_MODEL_PLANNER", os.getenv("GEMINI_MODEL_DEFAULT", "gemini-3.5-flash"))
    fallbacks = [m.strip() for m in os.getenv("GEMINI_MODEL_FALLBACKS", "").split(",") if m.strip()]
    for model in dict.fromkeys([default, *fallbacks]):
        started = time.monotonic()
        try:
            client.models.generate_content(model=model, contents="Reply with exactly: OK")
            elapsed = time.monotonic() - started
            reachable.append(model)
            print(f"{OK} {model:28} {elapsed:4.1f}s")
        except Exception as e:  # noqa: BLE001 - reporting, not handling
            text = str(e).lower()
            why = ("daily quota used up - it resets, and the next model in the chain covers it" if "quota" in text
                   else "overloaded right now - transient, retried automatically" if "503" in text or "unavailable" in text
                   else "not available to this key (404)" if "404" in text
                   else str(e)[:60])
            print(f"{WARN} {model:28} {why}")
    if not reachable:
        print(f"{WARN} No model is reachable, so the deterministic planner will run.")
else:
    print(f"{INFO} Skipped - no key configured.")

# ── 3. service + shared secret ──────────────────────────────────────────
step(3, "Agent service and the shared secret")
token = os.getenv("AGENT_SERVICE_INTERNAL_TOKEN", "").strip()
base = f"http://127.0.0.1:{os.getenv('AGENT_SERVICE_PORT', '8001')}"
try:
    import httpx

    with httpx.Client(timeout=5) as http:
        if http.get(f"{base}/health").json().get("status") == "ok":
            print(f"{OK} Service is up on {base}")
        else:
            fail("The agent service answered /health oddly.")

        # A wrong token must be refused, and the real one accepted. 422 means
        # the token passed and only the empty body was rejected.
        if http.post(f"{base}/schedule/plan", headers={"Authorization": "Bearer wrong"}, json={}).status_code == 401:
            print(f"{OK} A wrong token is refused (401)")
        else:
            fail("The service accepted a wrong token - check AGENT_SERVICE_INTERNAL_TOKEN.")

        code = http.post(f"{base}/schedule/plan", headers={"Authorization": f"Bearer {token}"}, json={}).status_code
        if code == 422:
            print(f"{OK} The configured token is accepted")
            print(f"{INFO} ASP.NET Core must send this same value as AgentService:InternalToken")
        elif code == 401:
            fail("The service rejected this .env token. It does not match its own AGENT_SERVICE_INTERNAL_TOKEN.")
        else:
            fail(f"Unexpected response to an empty request: HTTP {code}.")
except Exception as e:  # noqa: BLE001
    fail(f"The agent service is not reachable at {base} ({type(e).__name__}). "
         f"Start it with: uvicorn main:app --port 8001")

# ── 4. the agents themselves ────────────────────────────────────────────
step(4, "The four agents, end to end")
try:
    import gemini_client
    from agents import schedule_copilot
    from tests.schedule_fakes import FakeBackend
    from tests.test_schedule_copilot import NOW, request

    # A self-contained backend, so this checks the agents rather than whether
    # the database happens to hold suitable demo data today.
    backend = FakeBackend()
    backend.add_resource("p1", "Galle Fort Villa", coords=(6.0267, 80.2170))
    backend.add_resource("p2", "Unawatuna Beach House", coords=(6.0106, 80.2489))
    gemini_client.reset_call_log()
    gemini_client.reset_breakers()

    started = time.monotonic()
    trace = schedule_copilot.run(
        request("Line up 4 property viewings for Thursday's buyers, mornings only, "
                "and leave time to drive between houses",
                target=4, duration=45, business_type="RealEstate"),
        backend.client(), now=NOW)
    elapsed = time.monotonic() - started

    ran = [s.agent for s in trace.agent_steps if s.ok]
    expected = ["PlannerAgent", "DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"]
    print(f"{OK if ran == expected else BAD} All four agents ran: {' -> '.join(a.replace('Agent', '') for a in ran)}")
    if ran != expected:
        fail(f"Only these agents completed: {ran}. Error: {trace.error}")

    planner = trace.planner
    if planner and not planner.used_fallback:
        print(f"{OK} Gemini wrote the plan (confidence {planner.confidence_score:.2f})")
        print(f"       It read from the sentence: rules={planner.intent.priority_rules}, "
              f"weekdays={planner.intent.weekdays}, window={planner.intent.time_window}")
    else:
        print(f"{WARN} The DETERMINISTIC planner ran - Gemini was unavailable.")
        print("       The agents still work; only the objective's reading is simpler.")

    tools = sorted({c.tool for c in trace.tool_calls if c.success})
    print(f"{OK if len(tools) >= 5 else WARN} {len(trace.tool_calls)} allow-listed tool calls: {', '.join(tools)}")

    failed_checks = [c.rule for c in (trace.safety.checks if trace.safety else []) if c.status == "fail"]
    print(f"{OK if trace.status in ('Completed', 'AwaitingApproval') else BAD} "
          f"Status {trace.status} - {len(trace.action.proposals) if trace.action else 0} booking(s) proposed in {elapsed:.1f}s")
    if failed_checks:
        fail(f"Safety checks failed: {failed_checks}")
    if trace.status not in ("Completed", "AwaitingApproval"):
        fail(f"The pipeline ended as {trace.status}: {trace.error}")
except Exception as e:  # noqa: BLE001
    fail(f"The pipeline could not run: {type(e).__name__}: {e}")

# ── verdict ─────────────────────────────────────────────────────────────
print("\n" + "=" * 62)
if problems:
    print("NOT READY\n")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print("READY - the Agentic AI subsystem is working end to end.")
print("\nNext: log in to the web app as Admin or Manager, open Schedule Copilot,")
print("and run it against your real data.")
