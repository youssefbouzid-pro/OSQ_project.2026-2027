# API and Data Model

## API Principles

The API should be simple and session-oriented.

Recommended API style:

- REST-like HTTP API
- JSON responses
- Token-based authentication for PoC
- Role-based authorization

## Authentication

The PoC uses personal access tokens. There is no login endpoint.

### Token issuance

Tokens are provisioned once at deploy time and distributed out of band:

1. `scripts/seed_users.py` generates a random token per seeded user.
2. Only the SHA-256 hash is written to the `users` table as `tokenHash`.
3. The plaintext token is printed once and given to the learner out of band.
   It is never stored, logged, or written to Git.
4. Revocation sets `isActive = false`.

The seed script is run by `make seed-users` and is idempotent: an existing
`tokenHash` is left untouched.

### Request authentication

Every request carries:

    Authorization: Bearer <token>

The session handler hashes the presented token, looks up `tokenHash` in the
`users` table, and rejects the request with `401` if no active user matches.
Authorization is then applied per the matrix at the end of this document.

Tokens must only be transmitted over HTTPS. Plaintext tokens must never appear
in logs or error messages.

## Core Endpoints

### Authentication

    GET /me

Returns current user profile.

### Labs

    GET /labs

Returns available labs.

    GET /labs/{labId}

Returns lab details and task metadata.

**Flags are never returned by this endpoint.** `expectedFlag` stays server-side
only. See [Flag Model](#flag-model).

### Sessions

    POST /labs/start

Body:

    {
      "labId": "linux-beginner"
    }

Creates a new lab session.

    GET /sessions

Returns sessions visible to the current user.

    GET /sessions/{sessionId}

Returns session details.

    POST /sessions/{sessionId}/destroy

Ends an active session.

### Flags

    POST /sessions/{sessionId}/flags

Body:

    {
      "taskId": "linux-b-1",
      "flag": "CB-LINUX-B-01"
    }

Submits a flag for validation.

### Activity

    GET /activity

Admin/auditor only.

Returns platform events.

## Indexes

Two access patterns need a global secondary index. Neither changes the
attributes above:

- `users` carries `by-token-hash` (hash key `tokenHash`), so a request
  resolves a token in one lookup instead of a scan.
- `sessions` carries `by-user` (hash key `userId`, range key
  `createdAt`), so a learner's sessions list most-recent-first.

No DynamoDB TTL is enabled on `sessions`. Terminated sessions must
survive for audit history (see
[04-session-lifecycle-and-ttl.md](04-session-lifecycle-and-ttl.md) and
[05-platform-architecture.md](05-platform-architecture.md)), so retention
is a process concern rather than a TTL one.

## Recommended DynamoDB Tables

### users

Primary key:

    userId

Attributes:

    userId
    email
    role
    tokenHash
    maxConcurrentLabs
    isActive

### labs

Primary key:

    labId

Attributes:

    labId
    family
    level
    name
    description
    instanceType
    amiParameter
    ttlMinutes
    tasks

### sessions

Primary key:

    sessionId

Attributes:

    sessionId
    userId
    labId
    state
    createdAt
    expiresAt
    endedAt
    instanceId
    tailscaleHostname
    flags
    terminationReason

### activity

Primary key:

    eventId

Attributes:

    eventId
    at
    kind
    level
    message
    userId
    sessionId

## Session States

    REQUESTED
    PENDING
    PROVISIONING
    TAILSCALE_ENROLLMENT
    READY
    EXPIRING
    TERMINATING
    TERMINATED
    FAILED

## Flag Model

### Server-side record (never serialized)

The `labs` table stores the authoritative task record, including the expected
flag:

    taskId
    title
    instruction
    hint
    expectedFlag

Example:

    {
      "taskId": "linux-b-1",
      "title": "Locate the application config",
      "instruction": "Find the config file inside /opt/app.",
      "hint": "Use ls -la /opt/app",
      "expectedFlag": "CB-LINUX-B-01"
    }

### Client-side view (what `GET /labs` and `GET /labs/{labId}` return)

The `expectedFlag` field is stripped before the response is serialized. The
client receives the same record minus `expectedFlag`:

    {
      "taskId": "linux-b-1",
      "title": "Locate the application config",
      "instruction": "Find the config file inside /opt/app.",
      "hint": "Use ls -la /opt/app"
    }

Returning `expectedFlag` would hand every learner every answer, so this
redaction is a hard rule, not an optimization. It is covered by an API test in
[17-ci-cd-and-governance.md](17-ci-cd-and-governance.md).

### Validation

`POST /sessions/{sessionId}/flags` trims and upper-cases the submitted value,
compares it to `expectedFlag`, and records the result. The learner may only see
whether the submission was accepted.

### Session completion state

Session flags store completed task IDs:

    {
      "flags": {
        "linux-b-1": true,
        "linux-b-2": false
      }
    }

## Event Kinds

Recommended activity events:

    AUTH_SIGN_IN
    LAB_REQUESTED
    LAB_PROVISIONING
    LAB_READY
    LAB_FAILED
    FLAG_SUBMITTED
    FLAG_ACCEPTED
    FLAG_REJECTED
    LAB_TERMINATED_BY_USER
    LAB_TERMINATED_BY_TTL
    LAB_TERMINATED_BY_ADMIN

## Authorization Rules

| Endpoint | Student | Admin | Auditor |
|---|---:|---:|---:|
| GET /me | Yes | Yes | Yes |
| GET /labs | Yes | Yes | Limited |
| POST /labs/start | Yes | Yes | No |
| GET /sessions | Own | All | Read-only |
| POST /sessions/{id}/destroy | Own | Any | No |
| POST /sessions/{id}/flags | Own | Yes | No |
| GET /activity | No | Yes | Yes |
