"""Audit event writer.

Every meaningful action appends a row to the ``activity`` table
(``docs/16``, ``docs/09``). Events are append-only: nothing updates or
deletes them.
"""

import uuid
from datetime import datetime, timezone

# Event kinds defined in docs/16 "Event Kinds".
AUTH_SIGN_IN = "AUTH_SIGN_IN"
LAB_REQUESTED = "LAB_REQUESTED"
LAB_PROVISIONING = "LAB_PROVISIONING"
LAB_READY = "LAB_READY"
LAB_FAILED = "LAB_FAILED"
FLAG_SUBMITTED = "FLAG_SUBMITTED"
FLAG_ACCEPTED = "FLAG_ACCEPTED"
FLAG_REJECTED = "FLAG_REJECTED"
LAB_TERMINATED_BY_USER = "LAB_TERMINATED_BY_USER"
LAB_TERMINATED_BY_TTL = "LAB_TERMINATED_BY_TTL"
LAB_TERMINATED_BY_ADMIN = "LAB_TERMINATED_BY_ADMIN"

LEVEL_INFO = "INFO"
LEVEL_WARN = "WARN"
LEVEL_ERROR = "ERROR"


def utc_now():
    return datetime.now(timezone.utc)


def iso(value=None):
    value = value or utc_now()
    if isinstance(value, str):
        return value
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def record(repo, kind, message, level=LEVEL_INFO, user=None, session_id=None, at=None):
    """Append one activity event. Never raises into the caller's path."""
    event = {
        "eventId": str(uuid.uuid4()),
        "at": at or iso(),
        "kind": kind,
        "level": level,
        "message": message,
    }
    if user:
        event["userId"] = user.get("userId")
    elif user is None:
        pass
    if session_id:
        event["sessionId"] = session_id

    repo.put_event(event)
    return event
