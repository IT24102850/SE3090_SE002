# Test Execution Summary

## Execution record

Date: 2026-10-02

The commands below were executed against the working tree. Counts are current results, not historical usage-log claims.

| Layer | Command | Result |
|---|---|---|
| Backend | `dotnet test backend/SmeBackend.Tests/SmeBackend.Tests.csproj --configuration Release --logger "trx;LogFileName=assignment-backend.trx"` | 595 passed, 0 failed, 15 skipped, 610 total |
| React | `cd frontend; npm run test -- --reporter=dot` | 194 passed, 0 failed, 22 files |
| React build | `cd frontend; npm run build` | Passed: nav parity, subtype registry, TypeScript, Vite/PWA build |
| Agentic AI | `cd agentic-ai-service; python -m pytest tests/ -q` | 194 passed, 0 failed, 2 warnings |
| Flutter analysis | `cd mobile/sme_mobile; flutter analyze` | No issues found |
| Flutter tests | `cd mobile/sme_mobile; flutter test` | 154 passed, 0 failed |
| Frontend dependency security | `cd frontend; npm audit --audit-level=high` | 0 vulnerabilities after remediation |
| k6 performance | `k6 run tests/performance/load-test.js` | Historical deployed evidence: 5 VUs passed; 20 VUs exceeded thresholds and exposed 429/5xx saturation |

## Interpretation

The functional baseline is green across all four implementation layers. The backend result includes 15 skipped PostgreSQL/Testcontainers cases, so the database integration claim is reproducible but not fully executed on this machine. These must be rerun with Docker and attached as TRX evidence for the strongest database mark.

The React suite initially had one timeout. It was fixed with a test-specific timeout because the focused test passed quickly and the full suite was the only failing condition. The full suite and production build were then rerun successfully.

The performance evidence demonstrates both a passing low-load profile and an honest saturation boundary. At 5 concurrent users the recorded failure rate was 0.99% and thresholds passed. At 20 users the deployment experienced latency degradation and HTTP 429/5xx responses. This is reported as a capacity finding, not converted into a false pass.

## Required attached evidence

- Backend TRX: generated under `backend/SmeBackend.Tests/TestResults/` after the recorded run.
- Agent JUnit XML: `tests/evidence-agent-pytest.xml`.
- Frontend console output: rerun command and capture to a file for final submission.
- Flutter console output: rerun command and capture to a file for final submission.
- Coverage reports: generate before submission where supported; current repo has broad tests but no checked-in coverage threshold report.
- k6 raw JSON and Markdown summaries under `tests/performance/results/`.
- Screenshots: capture the live integrated workflow with test ID, timestamp, URL, and sanitized data.
- Git evidence: include `git log --stat`, per-member `git log --author`, and links to testing commits.

## Conclusion

The system demonstrates strong automated functional coverage, deterministic AI safety behavior, authorization controls, mobile/web validation, and a remediated dependency security baseline. The remaining release gates for an Excellent submission are evidence collection: Docker-backed database execution, authenticated k6 scenarios, coverage exports, and a live cross-platform workflow demonstration. Those are explicitly tracked rather than claimed without proof.
