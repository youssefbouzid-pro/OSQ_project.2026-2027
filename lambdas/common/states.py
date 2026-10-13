"""Canonical session states.

Single source of truth is ``docs/04-session-lifecycle-and-ttl.md``. The
values here must never drift from that table: they are written to the
DynamoDB ``sessions.state`` attribute, returned by the API, and rendered
by the frontend.
"""

REQUESTED = "REQUESTED"
PENDING = "PENDING"
PROVISIONING = "PROVISIONING"
TAILSCALE_ENROLLMENT = "TAILSCALE_ENROLLMENT"
READY = "READY"
EXPIRING = "EXPIRING"
TERMINATING = "TERMINATING"
TERMINATED = "TERMINATED"
FAILED = "FAILED"

ALL_STATES = (
    REQUESTED,
    PENDING,
    PROVISIONING,
    TAILSCALE_ENROLLMENT,
    READY,
    EXPIRING,
    TERMINATING,
    TERMINATED,
    FAILED,
)

#: States in which a session still occupies the learner's quota.
ACTIVE_STATES = frozenset(
    {
        REQUESTED,
        PENDING,
        PROVISIONING,
        TAILSCALE_ENROLLMENT,
        READY,
        EXPIRING,
        TERMINATING,
    }
)

#: States the state machine cannot leave (``docs/04``, ``--> [*]``).
TERMINAL_STATES = frozenset({TERMINATED, FAILED})

#: States in which a lab instance may exist and must be reaped by the GC.
#: ``FAILED`` is terminal for the learner but an instance may still be
#: running, so the garbage collector still looks at it.
STATES_WITH_INSTANCE = frozenset(
    {
        PROVISIONING,
        TAILSCALE_ENROLLMENT,
        READY,
        EXPIRING,
        TERMINATING,
        FAILED,
    }
)


def is_active(state):
    """True when the session still counts against the learner's quota."""
    return state in ACTIVE_STATES


def is_terminal(state):
    """True when the session can no longer change state."""
    return state in TERMINAL_STATES
