# Viva Demonstration Guide

Each student should choose one test they personally wrote or materially changed, run it live, explain the failure it protects against, and modify one input to show the assertion is meaningful.

## Suggested individual demonstrations

### Booking / AI workflow
1. Run the targeted xUnit disruption approval test.
2. Explain why the workflow remains `AwaitingApproval` and why an objective cannot override the safety gate.
3. Show the corresponding pytest golden case and the persisted audit fields.
4. Change the proposed resource or approval selection and explain the expected result.

### Billing / forms
1. Run a billing xUnit or React dynamic-form test.
2. Explain validation boundaries, approval thresholds, and why model output cannot change deterministic limits.
3. Run the invalid discount or payment case and show the error assertion.

### Inventory / mobile / security
1. Run `InventoryManagerPage.test.tsx` or a Flutter inventory test.
2. Explain the invalid, valid, and confirmation paths and the API payload assertion.
3. Show `npm audit --audit-level=high` returning zero vulnerabilities and explain that the dependency fix was retested.

## Questions to prepare

- Why was this framework selected instead of manual observation?
- What does a skipped Testcontainers test mean, and why is it not a pass?
- Which assertion would fail if the bug returned?
- How does tenant isolation work and where is it tested?
- How does the AI service handle malformed model output or prompt injection?
- Which actions require human approval and where is that enforced?
- What did the 20-VU k6 result show, and why is it still useful despite failing thresholds?
- What is mocked, what is real, and what limitation does that create?
- How would you reproduce the defect and prove the fix?
- Which commit contains your contribution, and what files did you own?

## Demonstration discipline

Use sanitized credentials, do not expose tokens or connection strings, and keep a clean test tenant. Explain the command, setup, input, expected output, actual output, and conclusion. If a prerequisite is missing, say so and show the reproducible command instead of inventing a result.
