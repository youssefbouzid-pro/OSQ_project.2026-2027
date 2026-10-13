/*
 * Smoke test for the browser API mock (frontend/api.js).
 *
 * Run with:  node frontend/smoke.test.js     (or: make test-frontend)
 *
 * The assertions double as a regression net for the one property that
 * must never break (docs/16 "Flag Model"): `expectedFlag` and the answer
 * strings themselves never appear in anything the app can render.
 */

global.window = {};
require(require("path").join(__dirname, "api.js"));
const api = global.window.LabAPI;

function assert(cond, msg) { if (!cond) { console.error("FAIL:", msg); process.exitCode = 1; } else { console.log("ok  -", msg); } }

(async () => {
  const me = await api.me("cldy_token_student01");
  assert(me.userId === "student-01" && me.role === "student", "GET /me returns the student");

  const labs = api.listLabs("cldy_token_student01");
  assert(labs.length === 9, "catalog has 9 labs");
  assert(labs.every(l => l.labId && l.family && l.instanceType && l.ttlMinutes), "labs carry docs/16 fields");
  assert(labs.every(l => l.tasks.every(t => t.taskId && t.title && !("expectedFlag" in t) && !("id" in t))), "tasks are redacted and use taskId");

  const auditorLabs = api.listLabs("cldy_token_auditor01");
  assert(auditorLabs.every(l => !l.tasks), "auditor catalog omits tasks");

  const raw = JSON.stringify({ me, labs, sessions: api.listSessions("cldy_token_student01"), activity: api.listActivity() });
  assert(!raw.includes("expectedFlag") && !raw.includes("CB-"), "no expectedFlag or answer leaks anywhere");

  const session = await api.startLab("cldy_token_student01", { labId: "linux-beginner" });
  assert(session.sessionId && session.userId === "student-01" && session.state === "REQUESTED", "POST /labs/start creates a session");
  assert(/^\d{4}-\d{2}-\d{2}T/.test(session.createdAt), "timestamps are ISO-8601");
  assert("labType" in session === false && "ttlMinutes" in session === false, "session has no non-docs/16 fields");

  await new Promise(r => setTimeout(r, 5000));
  const ready = api.listSessions("cldy_token_student01").find(s => s.sessionId === session.sessionId);
  assert(ready.state === "READY", "session reached READY");
  assert(api.fqdn(ready).endsWith("cloudybt-tounsi.ts.net"), "fqdn built from tailscaleHostname");

  const good = await api.submitFlag("cldy_token_student01", session.sessionId, "linux-b-1", " cb-linux-b-01 ");
  assert(good.correct === true, "flag accepted, trimmed and case-insensitive");
  assert(ready.flags["linux-b-1"] === true, "flags map keyed by taskId");
  const bad = await api.submitFlag("cldy_token_student01", session.sessionId, "linux-b-2", "nope");
  assert(bad.correct === false, "wrong flag rejected");

  const ended = await api.destroyLab("cldy_token_student01", session.sessionId, "user");
  assert(ended.state === "TERMINATED" && ended.terminationReason === "user", "destroy sets terminationReason");
  const ttlDemo = await api.destroyLab("cldy_token_student01", "sess-44102", "ttl");
  assert(ttlDemo.terminationReason === "ttl", "TTL path records reason ttl");

  assert(api.quota("cldy_token_student01").active === 1, "quota counts remaining active sessions");
  assert(api.totalCost("cldy_token_student01") > 0, "cost computed from createdAt and instanceType");
  assert(api.canStart("cldy_token_auditor01") === false, "auditor cannot start labs");

  const kinds = new Set(api.listActivity().map(e => e.kind));
  assert(kinds.has("LAB_READY") && kinds.has("FLAG_ACCEPTED") && kinds.has("LAB_TERMINATED_BY_TTL"), "docs/16 event kinds emitted");

  const again = await api.me("cldy_token_revoked").catch(e => e);
  assert(again.code === "UNAUTHORIZED", "revoked token rejected");
})();
