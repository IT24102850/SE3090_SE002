# Excellent Rubric Evidence Matrix

| Excellent criterion | Required demonstration | Repository evidence | Final evidence action |
|---|---|---|---|
| Group: Testing Strategy & Coverage (10) | Relevant components, risks, planned tools, meaningful cases | `TEST_PLAN.md`, `TEST_CASES.md`, broad backend/React/Flutter/AI suites | Attach matrix and CI run links |
| Group: Integrated & Non-Functional Testing (15) | Integrated/E2E workflow plus performance and security | API approval lifecycle tests, k6 results, npm audit 0 vulnerabilities | Execute E2E-001 and authenticated k6; attach screenshots and raw output |
| Group: Overall Results, Defects & Documentation (15) | Complete traceable results, defects, fixes, retesting, required documents | All documents in this folder; DEF-001 closed; execution counts | Add Docker TRX, coverage, live screenshots, and final PDF |
| Individual: Testing Tool / Framework Demonstration (15) | Personally explain setup, configuration, purpose, and actual use | xUnit, Vitest/Testing Library, pytest/Pydantic, flutter_test, k6 commands | Each student selects one owned test and records a short demo or viva script |
| Individual: Test Implementation & Execution (15) | Own meaningful tests with normal, invalid, edge, failure cases | Test case IDs map to named source files; current suites green | Add commit links and demonstrate modifying/rerunning one test |
| Individual: Results, Defects & Retesting (10) | Interpret result, cause/fix, retest evidence | DEF-001 and SF-001 with before/after results | Attach terminal output and PR/commit references |
| Individual: Technical Contribution (5) | Ownership visible in tests, Git history, fixes, evidence | `README.md` ownership table, source paths, CI workflow | Add repository URL and `git log --author` extracts |
| Individual: Viva & Technical Understanding (15) | Explain tools, tests, results, limitations, and troubleshooting | `VIVA_GUIDE.md`, reproducible commands, known limitations | Rehearse live run; do not submit a test a member cannot explain |

## Evidence integrity rules

- A skipped test is not a pass.
- A historical result is not a current result.
- A mocked model test proves orchestration and safety logic, not live model quality.
- A component test is not a cross-client E2E test.
- Performance failures at 20 VUs must be reported and interpreted.
- Screenshots must come from this system and include enough context to be independently understood.
