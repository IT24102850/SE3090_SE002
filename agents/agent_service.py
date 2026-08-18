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

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Agent Workflows Service")

# Enable CORS for the frontend dev server(s) so the browser can call this service.
# In production, narrow allowed origins to your real frontend hosts.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



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


@app.get("/workflows")
def workflows_list(
    limit: int = 20,
    page: int = 1,
    pageSize: int = 20,
    status: str | None = None,
    tenantId: str | None = None,
    actionType: str | None = None,
    search: str | None = None,
):
    """Return recent workflows with optional filtering, pagination, and search."""
    _ensure_db()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Build WHERE clauses
    where_clauses = []
    params: list[object] = []
    if status:
        where_clauses.append("status = ?")
        params.append(status)
    if tenantId:
        where_clauses.append("tenantId = ?")
        params.append(tenantId)
    if actionType:
        where_clauses.append("actionType = ?")
        params.append(actionType)
    if search:
        # search across payload, validation_result, and tool_result as text
        where_clauses.append("(payload LIKE ? OR validation_result LIKE ? OR tool_result LIKE ?)")
        like = f"%{search}%"
        params.extend([like, like, like])

    where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

    # Count total
    count_sql = f"SELECT COUNT(1) FROM AgentWorkflows {where_sql}"
    cur.execute(count_sql, params)
    total_count = cur.fetchone()[0]

    offset = max(0, (page - 1) * pageSize)
    sql = f"SELECT id, created_at, actionType, payload, userRole, tenantId, riskLevel, validation_result, tool_result, llm_response, status FROM AgentWorkflows {where_sql} ORDER BY created_at DESC LIMIT ? OFFSET ?"
    exec_params = params + [pageSize, offset]
    cur.execute(sql, exec_params)

    rows = []
    for r in cur.fetchall():
        (id_, created_at, actionType, payload, userRole, tenantId, riskLevel, validation_result, tool_result, llm_response, status) = r
        try:
            payload_obj = json.loads(payload) if payload else None
        except Exception:
            payload_obj = payload
        try:
            validation_obj = json.loads(validation_result) if validation_result else None
        except Exception:
            validation_obj = validation_result
        try:
            tool_obj = json.loads(tool_result) if tool_result else None
        except Exception:
            tool_obj = tool_result
        rows.append({
            "id": id_,
            "created_at": created_at,
            "actionType": actionType,
            "payload": payload_obj,
            "userRole": userRole,
            "tenantId": tenantId,
            "riskLevel": riskLevel,
            "validation_result": validation_obj,
            "tool_result": tool_obj,
            "llm_response": llm_response,
            "status": status,
        })
    conn.close()
    return {"items": rows, "total": total_count, "page": page, "pageSize": pageSize}


@app.post("/workflows/{workflow_id}/approve")
def workflows_approve(workflow_id: int, body: dict[str, Any]):
    approver = body.get("approverRole", "Manager")
    note = body.get("note")
    _ensure_db()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT actionType, payload, validation_result, tool_result FROM AgentWorkflows WHERE id = ?", (workflow_id,))
    row = cur.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Workflow not found")
    actionType, payload, validation_result, tool_result = row

    try:
        vr = json.loads(validation_result) if validation_result else {"auditLog": []}
    except Exception:
        vr = {"auditLog": []}
    audit = vr.get("auditLog", [])
    audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": approver, "actionType": "approval", "outcome": "approved", "details": {"note": note}})
    vr["auditLog"] = audit

    # Update status to approved first
    cur.execute("UPDATE AgentWorkflows SET validation_result = ?, status = ? WHERE id = ?", (json.dumps(vr), "approved", workflow_id))
    conn.commit()

    backend_result = None
    # If this was a generated purchase order, attempt to create a real PO in the backend
    try:
        if actionType == "generate_purchase_order" and tool_result:
            try:
                tr = json.loads(tool_result)
            except Exception:
                tr = tool_result
            # Expect branchId and supplierId in payload or tool_result
            try:
                payload_obj = json.loads(payload) if payload else {}
            except Exception:
                payload_obj = payload or {}

            branch_id = tr.get("branchId") or payload_obj.get("branchId") or tr.get("branch_id")
            supplier_id = tr.get("supplierId") or payload_obj.get("supplierId") or tr.get("supplier_id")
            qty = tr.get("quantity") or tr.get("qty")
            est_unit_cost = tr.get("estimatedUnitCost") or tr.get("estimated_unit_cost") or tr.get("unitCost")

            if branch_id and supplier_id:
                backend_url = os.environ.get("BACKEND_URL", "http://localhost:5000")
                api_token = os.environ.get("BACKEND_API_KEY")
                po_number = f"AI-PO-{workflow_id}-{int(datetime.utcnow().timestamp())}"
                create_payload = {"BranchId": branch_id, "SupplierId": supplier_id, "Number": po_number, "Status": "Placed"}
                headers = {"Content-Type": "application/json"}
                if api_token:
                    headers["Authorization"] = f"Bearer {api_token}"
                post_url = backend_url.rstrip("/") + "/api/purchase-orders"
                resp = requests.post(post_url, json=create_payload, headers=headers, timeout=10)
                if resp.ok:
                    backend_result = resp.json()
                    # append backend result to audit
                    audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": "system", "actionType": "place_po", "outcome": "success", "details": {"backend": backend_result}})
                    # update AgentWorkflows row tool_result to include backend response
                    try:
                        tr["backend_response"] = backend_result
                        cur.execute("UPDATE AgentWorkflows SET tool_result = ? WHERE id = ?", (json.dumps(tr), workflow_id))
                    except Exception:
                        cur.execute("UPDATE AgentWorkflows SET tool_result = ? WHERE id = ?", (json.dumps({"note": "backend_success", "response": backend_result}), workflow_id))
                    conn.commit()
                else:
                    err_text = resp.text
                    audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": "system", "actionType": "place_po", "outcome": "error", "details": {"status_code": resp.status_code, "body": err_text}})
            else:
                audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": "system", "actionType": "place_po", "outcome": "skipped", "details": {"reason": "missing branch or supplier id"}})
    except Exception as e:
        audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": "system", "actionType": "place_po", "outcome": "exception", "details": {"error": str(e)}})

    # persist audit changes
    vr["auditLog"] = audit
    cur.execute("UPDATE AgentWorkflows SET validation_result = ? WHERE id = ?", (json.dumps(vr), workflow_id))
    conn.commit()
    conn.close()

    # If backend_result succeeded and send_notification tool is available, attempt to notify procurement
    notify_result = None
    try:
        if backend_result is not None:
            try:
                # fire-and-forget notification via the allowed tool
                execute_allowed_tool("send_notification", {
                    "toRole": "Procurement",
                    "subject": f"PO placed: {backend_result.get('number') if isinstance(backend_result, dict) else po_number}",
                    "body": {"workflowId": workflow_id, "backend": backend_result}
                })
                notify_result = {"notified": True}
            except Exception as e:
                notify_result = {"notified": False, "error": str(e)}
    except Exception:
        notify_result = {"notified": False}

    return {"id": workflow_id, "status": "approved", "validation_result": vr, "backend_result": backend_result, "notification": notify_result}


@app.post("/workflows/{workflow_id}/reject")
def workflows_reject(workflow_id: int, body: dict[str, Any]):
    approver = body.get("approverRole", "Manager")
    reason = body.get("reason", "rejected by user")
    _ensure_db()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT validation_result FROM AgentWorkflows WHERE id = ?", (workflow_id,))
    row = cur.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Workflow not found")
    validation_result = row[0]
    try:
        vr = json.loads(validation_result) if validation_result else {"auditLog": []}
    except Exception:
        vr = {"auditLog": []}
    audit = vr.get("auditLog", [])
    audit.append({"timestamp": datetime.utcnow().isoformat() + "Z", "actorRole": approver, "actionType": "approval", "outcome": "rejected", "details": {"reason": reason}})
    vr["auditLog"] = audit
    cur.execute("UPDATE AgentWorkflows SET validation_result = ?, status = ? WHERE id = ?", (json.dumps(vr), "rejected", workflow_id))
    conn.commit()
    conn.close()
    return {"id": workflow_id, "status": "rejected", "validation_result": vr}


if __name__ == "__main__":
    print("This module exposes process_workflow() and a FastAPI app (app).")
