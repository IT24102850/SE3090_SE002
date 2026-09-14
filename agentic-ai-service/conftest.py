import os

# Test defaults so importing `main`/agent modules never fails on missing
# env vars. Individual tests override via monkeypatch where it matters.
os.environ.setdefault("AGENT_SERVICE_INTERNAL_TOKEN", "test-internal-token")
os.environ.setdefault("GEMINI_API_KEY", "test-key-not-used-because-agents-are-mocked")
os.environ.setdefault("BACKEND_API_BASE_URL", "http://testserver/api")
os.environ.setdefault("APPROVAL_BOOKING_COUNT_THRESHOLD", "20")
os.environ.setdefault("APPROVAL_REVENUE_THRESHOLD", "500")
os.environ.setdefault("MAX_APPOINTMENT_DURATION_MINUTES", "120")
