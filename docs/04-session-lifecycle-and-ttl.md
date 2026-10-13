# Lab Session Lifecycle and TTL

## Canonical State Enum

These exact enum values are the single source of truth. They are used by the
DynamoDB `sessions.state` attribute, the API in [16-api-and-data-model.md](16-api-and-data-model.md),
the Lambda handlers, and the frontend.

| Enum value | UI label |
|---|---|
| `REQUESTED` | Requested |
| `PENDING` | Pending |
| `PROVISIONING` | Provisioning |
| `TAILSCALE_ENROLLMENT` | Enrolling Tailscale |
| `READY` | Running |
| `EXPIRING` | Expiring |
| `TERMINATING` | Ending |
| `TERMINATED` | Ended |
| `FAILED` | Failed |

## Session Lifecycle

A lab session moves through the following states:

    REQUESTED
      -> PENDING
      -> PROVISIONING
      -> TAILSCALE_ENROLLMENT
      -> READY
      -> EXPIRING
      -> TERMINATING
      -> TERMINATED

A session may also enter:

    FAILED

`EXPIRING` is a derived display state: the API keeps `READY` and the UI shows
`EXPIRING` when less than five minutes remain. `TERMINATING` is entered by an
operator or by the garbage collector and is immediately followed by `TERMINATED`.

## State Definitions

### REQUESTED

The learner requested a lab.

### PENDING

The platform accepted the request and queued provisioning.

### PROVISIONING

The lab instance is being created from the approved launch template.

### TAILSCALE_ENROLLMENT

The lab node is joining the Tailscale network.

### READY

The lab is usable. The learner can connect and complete tasks.

### EXPIRING

The lab is close to TTL expiration. The UI warns the learner.

### TERMINATING

Termination has been requested or started. The instance is being released.

### TERMINATED

The lab has been destroyed. This is the terminal success state.

### FAILED

The lab could not be provisioned or enrolled.

## TTL Rules

- Default TTL: 60 minutes
- Maximum TTL: 60 minutes
- Extension: not allowed
- Expiration behavior: automatic termination
- Data retention: no persistent learner data by default

## Expiration Behavior

When TTL expires:

1. The session state becomes `EXPIRING`.
2. The UI warns the learner.
3. The garbage collector moves the session to `TERMINATING`.
4. The garbage collector terminates the lab instance.
5. The session state becomes `TERMINATED`.
6. An activity event is recorded.

## Garbage Collection

The garbage collector should detect:

- Active sessions past expires_at
- Orphaned instances with no active session
- Instances missing required tags
- Instances stuck in provisioning for too long

Check frequency: every minute, as defined in
[15-ephemeral-provisioning.md](15-ephemeral-provisioning.md).

## Session Metadata

Each session stores the attributes defined in
[16-api-and-data-model.md](16-api-and-data-model.md):

- sessionId
- userId
- labId
- state
- createdAt
- expiresAt
- endedAt
- instanceId
- tailscaleHostname
- flags
- terminationReason
