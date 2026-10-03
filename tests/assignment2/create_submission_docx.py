from pathlib import Path
from datetime import date

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs' / 'assignment-2' / 'SE3090_Assignment_2_Software_Testing_Report.docx'
REPOSITORY_URL = 'https://github.com/IT24102850/SE3090_SE002.git'

NAVY = '122B5C'
BLUE = '1F4E79'
ORANGE = 'F28C28'
LIGHT_BLUE = 'EAF2F8'
LIGHT_ORANGE = 'FFF2E2'
LIGHT_GREY = 'F3F5F7'
DARK = RGBColor(31, 41, 55)


def set_cell_shading(cell, fill):
    properties = cell._tc.get_or_add_tcPr()
    shading = properties.find(qn('w:shd'))
    if shading is None:
        shading = OxmlElement('w:shd')
        properties.append(shading)
    shading.set(qn('w:fill'), fill)


def set_cell_text(cell, text, bold=False, color=None, size=8.5):
    cell.text = ''
    paragraph = cell.paragraphs[0]
    paragraph.paragraph_format.space_after = Pt(0)
    run = paragraph.add_run(str(text))
    run.bold = bold
    run.font.name = 'Aptos'
    run.font.size = Pt(size)
    if color:
        run.font.color.rgb = RGBColor.from_string(color)
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def add_table(doc, headers, rows, widths=None, font_size=8.2):
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = 'Table Grid'
    header = table.rows[0].cells
    for index, value in enumerate(headers):
        set_cell_text(header[index], value, bold=True, color='FFFFFF', size=font_size)
        set_cell_shading(header[index], NAVY)
    for row_index, row in enumerate(rows):
        cells = table.add_row().cells
        for index, value in enumerate(row):
            set_cell_text(cells[index], value, size=font_size)
            set_cell_shading(cells[index], 'FFFFFF' if row_index % 2 == 0 else LIGHT_GREY)
    if widths:
        for row in table.rows:
            for index, width in enumerate(widths):
                row.cells[index].width = Inches(width)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)
    return table


def add_heading(doc, text, level=1):
    paragraph = doc.add_heading(text, level=level)
    paragraph.paragraph_format.space_before = Pt(10 if level == 1 else 6)
    paragraph.paragraph_format.space_after = Pt(4)
    return paragraph


def add_body(doc, text, bold_prefix=None):
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.space_after = Pt(5)
    paragraph.paragraph_format.line_spacing = 1.08
    if bold_prefix and text.startswith(bold_prefix):
        first = paragraph.add_run(bold_prefix)
        first.bold = True
        paragraph.add_run(text[len(bold_prefix):])
    else:
        paragraph.add_run(text)
    for run in paragraph.runs:
        run.font.name = 'Aptos'
        run.font.size = Pt(10)
        run.font.color.rgb = DARK
    return paragraph


def add_bullet(doc, text):
    paragraph = doc.add_paragraph(style='List Bullet')
    paragraph.paragraph_format.space_after = Pt(2)
    run = paragraph.add_run(text)
    run.font.name = 'Aptos'
    run.font.size = Pt(9.5)
    run.font.color.rgb = DARK
    return paragraph


def add_code(doc, text):
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.left_indent = Inches(0.25)
    paragraph.paragraph_format.space_after = Pt(5)
    run = paragraph.add_run(text)
    run.font.name = 'Consolas'
    run.font.size = Pt(8)
    run.font.color.rgb = DARK
    return paragraph


def add_status(doc, label, text, fill=LIGHT_BLUE):
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = 'Table Grid'
    cell = table.cell(0, 0)
    set_cell_shading(cell, fill)
    cell.text = ''
    paragraph = cell.paragraphs[0]
    paragraph.paragraph_format.space_after = Pt(0)
    run = paragraph.add_run(label + ': ')
    run.bold = True
    run.font.color.rgb = RGBColor.from_string(NAVY)
    run.font.name = 'Aptos'
    run.font.size = Pt(9.5)
    run = paragraph.add_run(text)
    run.font.name = 'Aptos'
    run.font.size = Pt(9.5)
    run.font.color.rgb = DARK
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run('Page ')
    run.font.name = 'Aptos'
    run.font.size = Pt(8)
    field = OxmlElement('w:fldSimple')
    field.set(qn('w:instr'), 'PAGE')
    paragraph._p.append(field)


def add_footer(section):
    footer = section.footer
    footer.is_linked_to_previous = False
    paragraph = footer.paragraphs[0]
    paragraph.text = 'SE3090 Assignment 2 | Software Testing and Quality Evaluation'
    paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
    for run in paragraph.runs:
        run.font.name = 'Aptos'
        run.font.size = Pt(8)
        run.font.color.rgb = RGBColor.from_string('667085')
    add_page_number(footer.add_paragraph())


def add_cover(doc):
    section = doc.sections[0]
    section.top_margin = Inches(0.65)
    section.bottom_margin = Inches(0.65)
    section.left_margin = Inches(0.75)
    section.right_margin = Inches(0.75)

    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.space_before = Pt(45)
    run = paragraph.add_run('SE3090')
    run.bold = True
    run.font.name = 'Aptos Display'
    run.font.size = Pt(27)
    run.font.color.rgb = RGBColor.from_string(NAVY)

    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run('Software Engineering Frameworks')
    run.bold = True
    run.font.name = 'Aptos Display'
    run.font.size = Pt(19)
    run.font.color.rgb = RGBColor.from_string(BLUE)

    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run('Assignment 2')
    run.bold = True
    run.font.name = 'Aptos Display'
    run.font.size = Pt(34)
    run.font.color.rgb = RGBColor.from_string(ORANGE)

    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.space_before = Pt(25)
    run = paragraph.add_run('Software Testing and Quality Evaluation\nof the SE3090 Integrated System')
    run.bold = True
    run.font.name = 'Aptos Display'
    run.font.size = Pt(20)
    run.font.color.rgb = DARK

    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.space_before = Pt(20)
    run = paragraph.add_run('BSc (Hons) in Information Technology - Software Engineering\nYear 3 Semester 1 - 2026')
    run.font.name = 'Aptos'
    run.font.size = Pt(12)
    run.font.color.rgb = DARK

    doc.add_paragraph().paragraph_format.space_before = Pt(35)
    add_table(doc, ['Document control', 'Value'], [
        ('Submission type', 'Group assignment with individual viva'),
        ('Maximum marks', '100'),
        ('Contribution to final grade', '15%'),
        ('Date prepared', '2026-10-03'),
        ('System under test', 'Universal SME Management Platform'),
        ('Repository', 'SE3090_SE002-clean'),
        ('Repository URL', REPOSITORY_URL),
    ], [2.0, 4.8], 9)

    add_status(doc, 'Evidence integrity', 'This report uses current repository execution results. Docker-backed database tests, authenticated k6 scenarios, and live cross-client acceptance are explicitly marked pending where they were not executed in the local environment.', LIGHT_ORANGE)

    doc.add_page_break()


def configure_styles(doc):
    styles = doc.styles
    normal = styles['Normal']
    normal.font.name = 'Aptos'
    normal.font.size = Pt(10)
    normal.font.color.rgb = DARK
    for name, size, color in [('Title', 24, NAVY), ('Heading 1', 16, NAVY), ('Heading 2', 12, BLUE), ('Heading 3', 10.5, BLUE)]:
        style = styles[name]
        style.font.name = 'Aptos Display'
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(color)


def main():
    doc = Document()
    configure_styles(doc)
    add_footer(doc.sections[0])
    add_cover(doc)

    add_heading(doc, 'Executive Summary', 1)
    add_body(doc, 'This report evaluates the actual SE3090 integrated platform rather than a theoretical sample. The system consists of an ASP.NET Core 8 Web API, PostgreSQL persistence, a React web application, a Flutter mobile application, and a FastAPI Agentic AI service. Testing was selected around the highest risks: booking conflicts, authorization and tenant isolation, database integrity, client/API contracts, AI safety and approval enforcement, performance, and dependency security.')
    add_body(doc, 'The fresh local execution baseline is strong: 595 backend tests passed, 194 React tests passed, 194 Agentic AI tests passed, and 154 Flutter tests passed. Flutter analysis and the React production build passed. The frontend dependency audit initially found four advisories; compatible updates were applied and the audit now reports zero vulnerabilities.')
    add_body(doc, 'The report distinguishes passed, skipped, diagnostic, and pending evidence. Fifteen PostgreSQL/Testcontainers tests were skipped because Docker was unavailable. The deployed authenticated k6 scenarios and the complete Flutter-to-API-to-React workflow still require final demonstration evidence. These limitations are recorded to preserve assessment integrity and to make the remaining viva preparation explicit.')
    add_status(doc, 'Overall assessment', 'The repository provides broad, meaningful automated coverage and a traceable evidence structure. The final Excellent mark depends on attaching the remaining live and environment-dependent evidence before CourseWeb submission.', LIGHT_ORANGE)

    add_heading(doc, '1. Assignment Alignment', 1)
    add_body(doc, 'The assignment requires planned testing of the same integrated system, use of appropriate frameworks, normal/invalid/boundary/failure cases, current execution results, defect and retest evidence, performance and security testing, tool-generated evidence, and an individual viva contribution. This report and its companion test-case and evidence files address those requirements.')
    add_table(doc, ['Assignment requirement', 'Evidence in this submission'], [
        ('Test plan', 'Scope, risks, objectives, tools, environment, responsibilities, schedule, and exit criteria in this report.'),
        ('Test cases', 'Traceable API, database, React, Flutter, AI, integration, performance, and security cases in Section 5.'),
        ('Actual results', 'Fresh execution totals and interpretation in Section 6, with passed/skipped/pending states.'),
        ('Defects and retesting', 'Inventory timeout defect and npm security finding in Section 7.'),
        ('Performance and security', 'k6 performance results and npm audit result in Section 8.'),
        ('Individual viva', 'Ownership, commands, explanations, and likely questions in Section 11.'),
    ], [2.2, 4.6])
    add_heading(doc, '1.1 Group Members and Individual Ownership', 2)
    add_table(doc, ['Student', 'Student ID', 'Primary component', 'Testing / AI contribution'], [
        ('Hasiru Chamika', 'IT24102850', 'Universal Booking & Resource Engine', 'Booking conflicts, availability, workflow approval, Schedule Copilot and booking Agentic AI safety tests.'),
        ('Oshadi', 'IT24101203', 'Billing, Payments & Dynamic Forms Engine', 'Billing, payment, invoice and dynamic-form tests plus Billing Copilot evidence.'),
        ('Hasaranga Abeyrathna', 'IT24102315', 'Inventory, Analytics & Intelligence Hub', 'Inventory, StockSense, mobile inventory and security/performance evidence.'),
    ], [1.4, 1.0, 1.8, 2.6], 7.8)
    add_status(doc, 'Group-size approval', 'This is a three-member group. The student identities and individual ownership are documented; the lecturer-in-charge written approval required by Section 3 must be attached before CourseWeb submission.', LIGHT_ORANGE)

    add_heading(doc, '2. System Under Test', 1)
    add_body(doc, 'The platform is a multi-tenant SME management system. Clients communicate with the ASP.NET Core API; the API owns authentication, authorization, tenant scoping, validation, booking rules, migrations, audit-sensitive operations, and database access. The Agentic AI service is an internal FastAPI boundary called by the API and uses allow-listed tools. High-impact actions remain subject to deterministic validation and human approval.')
    add_table(doc, ['Component', 'Technology', 'Testing focus'], [
        ('Backend/API', 'ASP.NET Core 8, EF Core, JWT, xUnit, Moq', 'HTTP behavior, validation, auth, roles, tenant isolation, booking and approval workflows.'),
        ('Database', 'PostgreSQL/Supabase, EF Core migrations', 'Constraints, foreign keys, uniqueness, transactions, migration and query behavior.'),
        ('Web', 'React 18, TypeScript, Vite, Redux Toolkit', 'Components, forms, protected routes, error states, AI workflow UI, build parity.'),
        ('Mobile', 'Flutter, Dart, Riverpod, Dio', 'Widgets, validation, navigation, API refresh behavior, QR check-in and inventory.'),
        ('Agentic AI', 'FastAPI, Pydantic, pytest, Gemini/Ollama boundary', 'Structured contracts, agent sequence, tool permissions, safety, failure recovery.'),
    ], [1.1, 2.2, 3.5])

    add_heading(doc, '3. Test Strategy and Quality Risks', 1)
    add_body(doc, 'The strategy uses a layered approach. Unit and service tests isolate business rules; API integration tests exercise controllers and authorization boundaries; database integration tests use PostgreSQL/Testcontainers; React and Flutter tests validate user-facing states; Agentic AI tests use deterministic model and backend fakes to make safety assertions repeatable; k6 and dependency audit provide non-functional evidence.')
    add_table(doc, ['Risk', 'Control and evidence', 'Priority'], [
        ('Double booking or invalid availability', 'Conflict, overlap, capacity, adjacent-slot, cancellation, and rescheduling tests.', 'Critical'),
        ('Cross-tenant data exposure', 'JWT, role, tenant, branch, and protected-route tests.', 'Critical'),
        ('Unsafe AI action', 'Pydantic contract checks, allow-list tests, injection tests, deterministic approval gates.', 'Critical'),
        ('Database corruption', 'PostgreSQL constraints, migration, transaction rollback, and relationship tests.', 'High'),
        ('Client/API drift', 'React and Flutter API adapter, error-state, and contract-like tests.', 'High'),
        ('Service saturation', 'k6 low-load pass and 20-VU diagnostic saturation run.', 'High'),
        ('Dependency vulnerability', 'npm audit, remediation, and post-fix audit.', 'High'),
    ], [2.0, 4.2, 0.6])

    add_heading(doc, '4. Environment, Tools, and Responsibilities', 1)
    add_table(doc, ['Area', 'Tool/framework', 'Responsible contribution'], [
        ('Backend/API', 'xUnit, Moq, WebApplicationFactory', 'Booking engine, authorization, controller and workflow tests.'),
        ('Database', 'EF Core, PostgreSQL, Testcontainers', 'Schema integrity, constraints, transactions, migrations.'),
        ('React', 'Vitest, Testing Library, jsdom', 'Protected routes, inventory, billing, booking and AI workflow UI.'),
        ('Flutter', 'flutter_test, Dio adapter fakes', 'Login, booking, QR check-in, inventory and navigation.'),
        ('Agentic AI', 'pytest, Pydantic, deterministic fakes', 'Golden cases, tool permissions, approval and safe failure.'),
        ('Performance', 'k6', 'Public endpoint latency, failure rate, concurrency and saturation.'),
        ('Security', 'npm audit plus authorization tests', 'Dependency remediation and behavioral authorization evidence.'),
    ], [1.2, 2.3, 3.3])
    add_body(doc, f'The three contributors are Hasiru Chamika (IT24102850), Oshadi (IT24101203), and Hasaranga Abeyrathna (IT24102315). Repository: {REPOSITORY_URL}. Per-member commit extracts should be attached from `git log --author` for the viva and individual contribution verification.')

    add_heading(doc, '5. Test Cases and Traceability', 1)
    add_body(doc, 'The following representative cases demonstrate normal, invalid, boundary, and failure-oriented design. The full companion matrix is stored in `docs/assignment-2/TEST_CASES.md`.')
    add_table(doc, ['ID', 'Scenario', 'Expected result', 'Result'], [
        ('API-001', 'Valid and invalid login', 'Valid user receives JWT; invalid input is rejected safely.', 'Passed'),
        ('API-002', 'Wrong role, tenant, or token', '401/403 response; no foreign data or mutation.', 'Passed'),
        ('API-003', 'Overlap, adjacency, capacity, cancellation', 'Illegal conflict rejected; allowed boundaries accepted.', 'Passed'),
        ('API-004', 'Disruption recovery approval lifecycle', 'Only accepted proposals apply; rejection is retained.', 'Passed'),
        ('DB-001', 'Migration, FK, unique, CHECK constraints', 'Invalid writes fail and valid schema is created.', 'Pending Docker'),
        ('WEB-001', 'Protected route roles', 'Redirect or render based on auth and role.', 'Passed'),
        ('WEB-002', 'Inventory invalid then valid price edit', 'Validation blocks bad input; valid PUT refreshes row.', 'Passed'),
        ('MOB-001', 'Login validation and token refresh', 'Validation shows; refresh retries once; refusal signs out.', 'Passed'),
        ('AI-001', 'Structured schedule output', 'Contract parses and trace has required fields/order.', 'Passed'),
        ('AI-002', 'High-impact action approval', 'Workflow remains AwaitingApproval.', 'Passed'),
        ('AI-003', 'Prompt injection and tool permissions', 'No privilege escalation or unallow-listed tool.', 'Passed'),
        ('E2E-001', 'Flutter request -> API -> React approval -> Flutter status', 'Same workflow state is visible across clients.', 'Pending live'),
        ('PERF-001', 'Five virtual users on public endpoints', 'Failure <1%; p95 thresholds pass.', 'Passed'),
        ('SEC-001', 'Frontend dependency audit', 'No high/critical advisories.', 'Passed'),
    ], [0.7, 2.2, 3.5, 0.8])

    add_heading(doc, '6. Test Execution Results', 1)
    add_body(doc, 'All results below were executed against the repository on 2026-10-02. They are not copied from historical usage logs.')
    add_table(doc, ['Layer', 'Command/tool', 'Actual result', 'Status'], [
        ('Backend', 'dotnet test, Release, TRX', '595 passed, 0 failed, 15 skipped, 610 total.', 'Passed with skips'),
        ('React', 'npm run test', '194 passed, 0 failed, 22 test files.', 'Passed'),
        ('React build', 'npm run build', 'Navigation parity, subtype registry, TypeScript, Vite/PWA build passed.', 'Passed'),
        ('Agentic AI', 'pytest tests/ -q', '194 passed, 0 failed, 2 warnings.', 'Passed'),
        ('Flutter analysis', 'flutter analyze', 'No issues found.', 'Passed'),
        ('Flutter tests', 'flutter test', '154 passed, 0 failed.', 'Passed'),
        ('Security', 'npm audit --audit-level=high', '0 vulnerabilities after remediation.', 'Passed'),
        ('Performance', 'k6 deployed evidence', '5 VUs: 0.99% failures and thresholds passed; 20 VUs: saturation and 429/5xx failures.', 'Diagnostic'),
    ], [1.2, 2.3, 3.1, 1.0])
    add_status(doc, 'Important interpretation', 'The 15 skipped backend tests are PostgreSQL/Testcontainers cases, not passes. Docker-backed execution is required for the strongest database evidence.', LIGHT_ORANGE)

    add_heading(doc, '7. Defects, Fixes, and Retesting', 1)
    add_table(doc, ['Defect', 'Cause', 'Fix', 'Retest result'], [
        ('DEF-001: Inventory test timeout', 'Async inventory workflow exceeded Vitest default 5-second timeout under the full suite.', 'Added a justified test-specific 15-second timeout; assertions and production code unchanged.', 'Full React suite: 194/194 passed.'),
        ('SF-001: npm advisories', 'Transitive brace-expansion, fast-uri, serialize-javascript, and undici advisories.', 'Ran compatible `npm audit fix`, updating the lockfile.', 'npm audit: 0 vulnerabilities.'),
    ], [1.5, 2.1, 2.5, 1.0])
    add_body(doc, 'The frontend timeout was first reproduced in the full suite, then the single test was rerun and passed in 702 ms with a longer timeout. The complete suite and production build were rerun after the change. This establishes a before/fix/retest chain suitable for the defect report.')

    add_heading(doc, '8. Non-Functional Testing', 1)
    add_heading(doc, '8.1 Performance testing', 2)
    add_body(doc, 'The k6 script uses ramping virtual users and measures health/database round trip, business directory, and public booking catalog endpoints. At five virtual users, the recorded run produced 1,014 requests, a 0.99% failure rate, and passing thresholds. At twenty virtual users, the deployment exceeded thresholds, with increased latency and HTTP 429/5xx responses. This is a meaningful capacity result: the test found the free-tier edge limit instead of hiding it.')
    add_body(doc, 'Authenticated-read and Agentic AI latency scenarios were not included in the historical run because approved demo credentials were unavailable. They must be executed before final submission and added to the evidence folder.')
    add_heading(doc, '8.2 Security testing', 2)
    add_body(doc, 'Behavioral security tests cover authentication, role authorization, tenant isolation, approval boundaries, prompt-injection resistance, and tool allow-lists. The frontend dependency scan initially found four advisories; remediation was applied and the final audit returned zero vulnerabilities. The exposed credential file `scripts/pass.txt` must be rotated and excluded from the final submission.')

    add_heading(doc, '9. Integrated Workflow Demonstration', 1)
    add_body(doc, 'The repository contains an auditable disruption recovery workflow. The supplied Mirissa Jetliner seed script creates four stranded bookings and ten guests on the Dawn Departure and leaves a Morning Cruise option for recovery. The intended demonstration is: seed the data, sign in, open Bookings -> Disruption Recovery, select the failed departure and tomorrow dates, run the recovery plan, inspect affected guests and safety checks, approve selected proposals, and verify the resulting booking state and audit trace.')
    add_body(doc, 'Repository unit and API integration tests already cover the approval lifecycle and the React disruption recovery page covers the UI states. A final live cross-platform acceptance must still be captured for E2E-001: customer/mobile request, API orchestration, React manager approval, API application, and mobile status refresh. This report deliberately does not claim that live flow as completed without its screenshot and trace ID.')
    add_code(doc, 'psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-disruption.sql')

    add_heading(doc, '10. Rubric Evidence Matrix', 1)
    add_table(doc, ['Rubric criterion', 'Excellent evidence already prepared', 'Final attachment needed'], [
        ('Testing strategy and coverage', 'Risk-based plan, layered tools, representative normal/invalid/boundary/failure cases.', 'Attach this report and full test-case matrix.'),
        ('Integrated and non-functional testing', 'API approval lifecycle, k6 performance, security audit and behavioral security tests.', 'Live E2E screenshots and authenticated k6 output.'),
        ('Results, defects, documentation', 'Fresh totals, defect/retest chain, report, companion documents and runner.', 'TRX, JUnit, coverage and screenshot attachments.'),
        ('Tool/framework demonstration', 'Commands and ownership mapped to xUnit, Vitest, pytest, Flutter, k6.', 'Each student demonstrates one owned test live.'),
        ('Test implementation and execution', 'Meaningful assertions across all clients and AI safety paths.', 'Git commit links and modified-test demonstration.'),
        ('Results, defects and retesting', 'DEF-001 and SF-001 include reproduction, fix and retest.', 'Attach raw before/after output.'),
        ('Technical contribution', 'Ownership table and source paths are documented.', 'GitHub URL and `git log --author` extracts.'),
        ('Viva and understanding', 'Viva guide contains explanations and likely questions.', 'Rehearse without exposing secrets.'),
    ], [1.7, 3.0, 2.3])

    add_heading(doc, '11. Individual Viva Preparation', 1)
    add_body(doc, 'Each student should select one test they personally implemented or materially changed, run it live, explain the risk, identify the assertion, and modify one input to show that the test is meaningful. Students should be ready to explain what is mocked, what is real, why a skipped test is not a pass, how the AI approval gate prevents unsafe action, and what the 20-VU k6 result means.')
    add_table(doc, ['Student focus', 'Recommended demonstration', 'Key explanation'], [
        ('Hasiru', 'Booking conflict or disruption approval xUnit test plus AI safety case.', 'Why only validated, approved proposals can be applied.'),
        ('Oshadi', 'Billing threshold or dynamic form React/xUnit test.', 'Why deterministic billing limits cannot be changed by model output.'),
        ('Hasaranga', 'Inventory price edit or Flutter inventory test plus npm audit.', 'How invalid input, valid save, API payload, and security remediation are verified.'),
    ], [1.1, 3.0, 2.9])

    add_heading(doc, '12. Reproducibility and Evidence Inventory', 1)
    add_body(doc, 'The companion directory `docs/assignment-2/` contains the Markdown test plan, test cases, defect log, execution summary, rubric matrix, and viva guide. The script `tests/assignment2/run-baseline.ps1` reruns the local gates and writes logs under `tests/evidence/assignment-2/`. The Agentic AI JUnit result generated during execution is stored at `tests/evidence-agent-pytest.xml`. Backend TRX output is generated under `backend/SmeBackend.Tests/TestResults/`.')
    add_code(doc, 'dotnet test backend/SmeBackend.Tests/SmeBackend.Tests.csproj --configuration Release --logger "trx;LogFileName=assignment-backend.trx"')
    add_code(doc, 'Set-Location frontend; npm ci; npm run test; npm run build; npm audit --audit-level=high')
    add_code(doc, 'Set-Location agentic-ai-service; python -m pytest tests/ -q --junitxml=../tests/evidence/assignment-2/agent-tests.xml')
    add_code(doc, 'Set-Location mobile/sme_mobile; flutter pub get; flutter analyze; flutter test')
    add_body(doc, 'Final attachments should include raw test output, coverage reports where available, k6 JSON/Markdown summaries, sanitized screenshots, GitHub repository and commit evidence, lecturer group-size approval, and the declared AI usage record.')

    add_heading(doc, '13. Final Submission Checklist', 1)
    checklist = [
        'Attach this report as PDF after reviewing the generated DOCX.',
        'Attach completed test-case document with expected, actual, and Pass/Fail status.',
        'Attach defect/bug report with reproduction and retesting evidence.',
        'Run Docker-backed PostgreSQL tests and attach the TRX result.',
        'Run authenticated and Agentic AI k6 scenarios and attach raw output.',
        'Demonstrate the complete Flutter -> API -> React -> API -> Flutter workflow and attach screenshots/trace ID.',
        'Generate and attach coverage reports and CI artifact links.',
        f'Include repository URL {REPOSITORY_URL}, per-member commit extracts, lecturer group-size approval, and AI declaration.',
        'Rotate the exposed credential in `scripts/pass.txt`; never submit or publish that credential.',
        'Ensure every group member can explain and reproduce their own testing contribution during the viva.',
    ]
    for item in checklist:
        add_bullet(doc, item)

    add_status(doc, 'Declaration of evidence status', 'This report is complete as a repository-grounded testing report. Any item labelled Pending requires execution and attachment before the final CourseWeb submission; no pending result has been fabricated.', LIGHT_ORANGE)

    doc.add_page_break()
    add_heading(doc, 'Appendix A - Evidence File Map', 1)
    add_table(doc, ['Evidence', 'Location'], [
        ('Test plan and scope', 'docs/assignment-2/TEST_PLAN.md'),
        ('Test cases', 'docs/assignment-2/TEST_CASES.md'),
        ('Defect and retest record', 'docs/assignment-2/DEFECT_LOG.md'),
        ('Execution summary', 'docs/assignment-2/EXECUTION_SUMMARY.md'),
        ('Rubric traceability', 'docs/assignment-2/RUBRIC_EVIDENCE_MATRIX.md'),
        ('Viva preparation', 'docs/assignment-2/VIVA_GUIDE.md'),
        ('Automated runner', 'tests/assignment2/run-baseline.ps1'),
        ('Backend tests', 'backend/SmeBackend.Tests/'),
        ('React tests', 'frontend/src/**/*.test.*'),
        ('Flutter tests', 'mobile/sme_mobile/test/'),
        ('Agent tests', 'agentic-ai-service/tests/'),
        ('Performance script/results', 'tests/performance/'),
        ('CI pipeline', '.github/workflows/ci.yml'),
    ], [2.2, 4.8])

    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == '__main__':
    main()
