import { defineRailway, github, project, service } from "railway/iac";

const repository = "hasaranga0630/SEF-Project";
const branch = "main";

export default defineRailway(() => {
  const api = service("sme-backend", {
    source: github(repository, {
      branch,
      rootDirectory: "backend/SmeBackend",
    }),
    // The API Dockerfile is in the service root. Railway detects and builds it.
    healthcheck: "/health",
    healthcheckTimeout: 300,
  });

  const agent = service("sme-agent-service", {
    source: github(repository, {
      branch,
      rootDirectory: "agentic-ai-service",
    }),
    build: "pip install -r requirements.txt",
    start: "uvicorn main:app --host 0.0.0.0 --port $PORT",
    healthcheck: "/health",
  });

  return project("SEF-Project", {
    resources: [api, agent],
  });
});
