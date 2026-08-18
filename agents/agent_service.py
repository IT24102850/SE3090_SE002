from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from typing import Any

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .validation_safety_agent_contract import ValidationSafetyInput
from .validation_safety_agent import evaluate_validation_safety
from .inventory_tools import execute_allowed_tool, ValidationError as ToolValidationError


import os

DB_PATH = os.path.join(os.path.dirname(__file__), 'agent_workflows.db')
OLLAMA_URL = os.environ.get('OLLAMA_URL', "http://localhost:11434")
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', "llama2")

app = FastAPI(title="Agent Workflows Service")


class WorkflowRequest(BaseModel):
    actionType: str
    payload: dict[str, Any]
    userRole: str
    tenantId: str
    riskLevel: str | None = "low"


def _ensure_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS AgentWorkflows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT,
            actionType TEXT,
            payload TEXT,
            userRole TEXT,
            tenantId TEXT,
            riskLevel TEXT,
            validation_result TEXT,
            tool_result TEXT,
            llm_response TEXT,
            status TEXT
        )
        """
    )
    conn.commit()
    conn.close()


def _insert_workflow(record: dict[str, Any]) -> int:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO AgentWorkflows (created_at, actionType, payload, userRole, tenantId, riskLevel, validation_result, tool_result, llm_response, status) VALUES (?,?,?,?,?,?,?,?,?,?)",
        (
            record.get("created_at"),
            record.get("actionType"),
            json.dumps(record.get("payload")),
            record.get("userRole"),
            record.get("tenantId"),
            record.get("riskLevel"),
            json.dumps(record.get("validation_result")) if record.get("validation_result") is not None else None,
            json.dumps(record.get("tool_result")) if record.get("tool_result") is not None else None,
            record.get("llm_response"),
            record.get("status"),
        ),
    )
    conn.commit()
    rowid = cur.lastrowid
    conn.close()
    return rowid


def call_ollama(prompt: str) -> str | None:
    """Attempt to call a local Ollama HTTP API. Try common endpoints and return text or None on failure."""
    try:
        # Try /api/generate (older) path
        url = OLLAMA_URL.rstrip("/") + "/api/generate"
        payload = {"model": OLLAMA_MODEL, "prompt": prompt}
        resp = requests.post(url, json=payload, timeout=5)
        if resp.ok:
            data = resp.json()
            # Try to extract text if present
            if isinstance(data, dict):
                return data.get("text") or data.get("response") or json.dumps(data)
            return str(data)
    except Exception:
        pass
    try:
        # Try /api/predict
        url = OLLAMA_URL.rstrip("/") + "/api/predict"
        payload = {"model": OLLAMA_MODEL, "prompt": prompt}
        resp = requests.post(url, json=payload, timeout=5)
        if resp.ok:
            data = resp.json()
            if isinstance(data, dict):
                return data.get("text") or data.get("response") or json.dumps(data)
            return str(data)
    except Exception:
        pass
    return None


def process_workflow(input_obj: ValidationSafetyInput) -> dict[str, Any]:
    """Run validation, tool execution (if allowed), and LLM reasoning; persist in AgentWorkflows DB."""
    _ensure_db()
    created_at = datetime.utcnow().isoformat() + "Z"
    record = dict(
        created_at=created_at,
        actionType=input_obj.actionType,
        payload=input_obj.payload,
        userRole=input_obj.userRole,
        tenantId=input_obj.tenantId,
        riskLevel=input_obj.riskLevel,
        validation_result=None,
        tool_result=None,
        llm_response=None,
        status="pending",
    )

    # Evaluate validation/safety
    validation = evaluate_validation_safety(input_obj)
    record["validation_result"] = validation

    if not validation.get("isAllowed"):
        record["status"] = "blocked"
        _insert_workflow(record)
        return {"status": "blocked", "validation": validation}

    # Allowed: execute tool if applicable
    tool_result = None
    try:
        # Determine tool name mapping: use actionType directly if it's an allowed tool
        tool_name = input_obj.actionType
        # safe map for common variants
        mapping = {
            "create_purchase_order": "generate_purchase_order",
            "generate_purchase_order": "generate_purchase_order",
            "update_inventory_count": "update_inventory_count",
            "send_notification": "send_notification",
            "predict_demand": "predict_demand",
            "query_historical_usage": "query_historical_usage",
        }
        if tool_name in mapping:
            tool_to_call = mapping[tool_name]
            tool_result = execute_allowed_tool(tool_to_call, input_obj.payload)
            record["tool_result"] = tool_result
            record["status"] = "completed"
        else:
            record["status"] = "no_tool"
    except ToolValidationError as e:
        record["status"] = "tool_error"
        record["tool_result"] = {"error": str(e)}
    except Exception as e:
        record["status"] = "tool_exception"
        record["tool_result"] = {"error": str(e)}

    # Ask LLM for reasoning/explanation (best-effort)
    try:
        prompt = f"Action: {input_obj.actionType}\nUserRole: {input_obj.userRole}\nTenant: {input_obj.tenantId}\nPayload: {json.dumps(input_obj.payload)}\nValidation: {json.dumps(validation)}\nToolResult: {json.dumps(tool_result)}\nProvide a concise reasoning and next steps."  # noqa: E501
        llm_resp = call_ollama(prompt)
        if llm_resp is None:
            llm_resp = "<no-llm-available>"
        record["llm_response"] = llm_resp
    except Exception as e:
        record["llm_response"] = f"<llm-error:{e}>"

    _insert_workflow(record)
    return {"status": record["status"], "validation": validation, "tool_result": tool_result, "llm": record["llm_response"]}


@app.post("/workflows/execute")
def workflows_execute(req: WorkflowRequest):
    try:
        input_obj = ValidationSafetyInput(
            actionType=req.actionType,
            payload=req.payload,
            userRole=req.userRole,
            tenantId=req.tenantId,
            riskLevel=req.riskLevel or "low",
        )
        input_obj.validate()
    except ToolValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))

    result = process_workflow(input_obj)
    return result


if __name__ == "__main__":
    print("This module exposes process_workflow() and a FastAPI app (app).")
