# SE3090 Assignment 2 Evidence Package

This directory is the submission working folder for **Software Testing and Quality Evaluation of the SE3090 Integrated System**.

## Evidence status

The evidence is separated into three states:

- **Executed**: run in this repository on 2026-10-02 and recorded in `EXECUTION_SUMMARY.md`.
- **Reproducible**: automated test source and command exist, but the local run needs an external prerequisite such as Docker or a deployed account.
- **Pending demonstration**: must be captured against the deployed system before final CourseWeb submission, especially the complete cross-platform workflow.

No result in this package should be changed from Pending to Passed without attaching the corresponding output, screenshot, log, or exported report.

## Documents

| Document | Purpose |
|---|---|
| `TEST_PLAN.md` | Scope, risks, environments, tools, responsibilities, schedule, and exit criteria |
| `TEST_CASES.md` | Traceable functional, integration, non-functional, and AI safety cases |
| `DEFECT_LOG.md` | Defects found, remediation, retesting, and residual issues |
| `EXECUTION_SUMMARY.md` | Current automated results and evidence inventory |
| `RUBRIC_EVIDENCE_MATRIX.md` | Mapping from the Excellent rubric to repository evidence |
| `VIVA_GUIDE.md` | Individual demonstration script and likely viva questions |

## Reproduction commands

Run from the repository root in PowerShell:

```powershell
dotnet test backend/SmeBackend.Tests/SmeBackend.Tests.csproj --configuration Release --logger "trx;LogFileName=assignment-backend.trx"
Set-Location frontend; npm ci; npm run test; npm run build; npm audit --audit-level=high; Set-Location ..
Set-Location agentic-ai-service; python -m pytest tests/ -q --junitxml=../tests/evidence-agent-pytest.xml; Set-Location ..
Set-Location mobile/sme_mobile; flutter pub get; flutter analyze; flutter test; Set-Location ..\..
```

For PostgreSQL/Testcontainers cases, start Docker Desktop and rerun the backend command. For the live workflow and k6 scenarios, use the deployed API, agent service, web app, and approved demo credentials. Never place passwords, tokens, or connection strings in this directory.

## Final submission checklist

- Replace all Pending items with dated evidence or explain the limitation.
- Attach the generated TRX/JUnit/coverage/performance/security outputs.
- Add screenshots with visible URL, timestamp, test name, and result.
- Add the GitHub repository URL and each student's testing commits.
- Add lecturer approval for the three-member group in the main report.
- Declare AI assistance according to the CLEAR framework and ensure every contributor can explain their own tests.
- Do not submit the exposed credential file `scripts/pass.txt`; rotate that credential and remove it from the repository history if it is real.
