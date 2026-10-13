# Security Threat Model

This document is internal. It should not be shown in the learner UI.

## Trust Boundaries

- Learner browser to frontend
- Frontend to API/backend
- Backend to cloud provisioning layer
- Cloud provisioning layer to lab instance
- Learner device to lab instance through Tailscale

## Threat Matrix

| Threat | Risk | Mitigation |
|---|---|---|
| Unauthorized lab access | Medium | Session ownership checks, Tailscale identity |
| Token leakage | High | HTTPS, hashed tokens, revocation |
| Public SSH exposure | High | Tailscale-only access, no public SSH |
| Lab runs longer than TTL | Medium | Garbage collector and expires-at tags |
| Orphaned lab instance | Medium | Scheduled cleanup and tag validation |
| Learner accesses another learner session | Medium | Role checks and session ownership |
| Flag guessing | Low | Random per-session flags in stronger implementation |
| Excessive lab creation | Medium | Quota and platform active-lab limit |
| Privilege escalation inside lab | Expected | Labs are isolated disposable environments |
| Data leakage from lab | Medium | No persistent data, automatic termination |

## PoC Limitations

- Multi-tenant isolation is simplified.
- Token auth is mocked.
- Tailscale enrollment may be simulated.
- Flags may be static.
- Activity storage may be in-memory.

## Production Hardening

Recommended improvements:

- Use OIDC/SSO authentication.
- Use hashed and rotated access tokens.
- Use short-lived Tailscale auth keys.
- Use per-session dynamic ACLs.
- Use random per-session flags.
- Persist audit logs.
- Add rate limiting.
- Add abuse detection.
