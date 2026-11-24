// Minimal stand-in for the Unify ASP.NET API, mirroring the routes the connector uses.
import http from "node:http";

export function startMockBackend() {
  const log = [];
  const state = { issued: 0, validTokens: new Set(), refreshTokens: new Set(), expireNext: false };
  const USER = { id: "11111111-1111-4111-8111-111111111111", email: "admin@clinic.lk", fullName: "Dr Admin",
    role: "Admin", tenantId: "22222222-2222-4222-8222-222222222222", branchId: null };
  const issue = () => {
    state.issued++;
    const a = `access-${state.issued}`, r = `refresh-${state.issued}`;
    state.validTokens.add(a); state.refreshTokens.add(r);
    return { accessToken: a, refreshToken: r, expiresAt: "2026-11-24T20:00:00Z", user: USER };
  };
  const server = http.createServer(async (req, res) => {
    let body = "";
    for await (const c of req) body += c;
    const url = new URL(req.url, "http://x");
    const json = body ? JSON.parse(body) : undefined;
    const auth = (req.headers.authorization ?? "").replace("Bearer ", "");
    log.push({ method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), body: json, auth });
    const send = (status, data) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(data === undefined ? "" : JSON.stringify(data));
    };
    const p = url.pathname.replace(/^\/api/, "").toLowerCase();
    if (p === "/auth/login") {
      return json.email === USER.email && json.password === "secret" ? send(200, issue()) : send(401, { message: "Invalid email or password" });
    }
    if (p === "/auth/refresh") {
      if (!state.refreshTokens.has(json.refreshToken)) return send(401, { message: "bad refresh" });
      state.refreshTokens.delete(json.refreshToken);
      return send(200, issue());
    }
    if (p === "/tenant/public") return send(200, [{ id: USER.tenantId, name: "Asia MediHealth" }]);
    if (state.expireNext) { state.expireNext = false; state.validTokens.clear(); }
    if (!state.validTokens.has(auth)) return send(401, undefined);

    if (p === "/auth/me") return send(200, USER);
    if (p === "/tenant") return send(200, { id: USER.tenantId, name: "Asia MediHealth", businessType: "Clinic" });
    if (p === "/bookings" && req.method === "GET") return send(200, { items: [
      { id: "66666666-6666-4666-8666-666666666666", startTime: "2026-11-25T04:30:00Z", endTime: "2026-11-25T05:00:00Z", status: "Confirmed" }], total: 1 });
    if (p === "/bookings" && req.method === "POST") return send(201, { id: "b-new", ...json });
    if (p === "/bookings/66666666-6666-4666-8666-666666666666") return send(200, { id: "66666666-6666-4666-8666-666666666666", startTime: "2026-11-25T04:30:00Z", endTime: "2026-11-25T05:15:00Z" });
    if (p === "/bookings/66666666-6666-4666-8666-666666666666/history") return send(200, [{ type: "Created", at: "2026-11-20T10:00:00Z" }]);
    if (p === "/bookings/66666666-6666-4666-8666-666666666666/reschedule") return send(200, { id: "66666666-6666-4666-8666-666666666666", ...json });
    if (p === "/bookings/66666666-6666-4666-8666-666666666666/cancel") return send(204);
    if (p === "/bookings/forbidden/cancel") return send(403, { message: "Cancellation cutoff has passed" });
    if (p.startsWith("/reports/clinic/")) return send(200, { view: p, kpis: { bookings: 12 } });
    if (p === "/bookings/available-slots") return send(200, [{ start: "2026-11-25T03:30:00Z", end: "2026-11-25T04:30:00Z" }]);
    if (p === "/resources/search-availability") return send(200, []);
    return send(404, { message: `mock: no route ${req.method} ${p}` });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () =>
    resolve({ url: `http://127.0.0.1:${server.address().port}`, log, state, close: () => server.close() })));
}
