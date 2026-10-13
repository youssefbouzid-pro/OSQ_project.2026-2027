"""Lab catalog helpers: task lookup, flag redaction, flag validation.

The redaction rules here are a hard security rule, not an optimisation
(``docs/16`` "Flag Model"): ``expectedFlag`` is server-side only and must
never appear in an API response.
"""

from .errors import bad_request, not_found

FLAG_KEY = "expectedFlag"


def normalize_flag(value):
    """Trim and upper-case a submitted flag, per docs/16."""
    if value is None:
        return ""
    if not isinstance(value, str):
        return ""
    return value.strip().upper()


def redact_task(task):
    """Return a copy of a task record with ``expectedFlag`` removed."""
    if not isinstance(task, dict):
        return task
    return {k: v for k, v in task.items() if k != FLAG_KEY}


def redact_lab(lab):
    """Strip server-side fields from a lab before it is serialized."""
    if not isinstance(lab, dict):
        return lab
    clean = {k: v for k, v in lab.items() if k != FLAG_KEY}
    tasks = clean.get("tasks")
    if isinstance(tasks, list):
        clean["tasks"] = [redact_task(t) for t in tasks]
    return clean


def public_lab(lab, include_tasks=True):
    """Build the client view of a lab.

    ``include_tasks=False`` covers the auditor's "Limited" visibility on
    ``GET /labs`` (``docs/16`` authorization matrix): the catalog is
    visible, the task content is not.
    """
    clean = redact_lab(lab)
    if not include_tasks:
        clean.pop("tasks", None)
    return clean


def find_task(lab, task_id):
    for task in (lab or {}).get("tasks") or []:
        if isinstance(task, dict) and task.get("taskId") == task_id:
            return task
    return None


def resolve_task(lab, task_id):
    task = find_task(lab, task_id)
    if task is None:
        raise not_found("Unknown task '{}' for this lab.".format(task_id))
    return task


def matches_flag(task, submitted):
    """Compare a submission to the stored answer."""
    expected = normalize_flag((task or {}).get(FLAG_KEY, ""))
    if not expected:
        # A task with no stored answer can never be accepted.
        return False
    return normalize_flag(submitted) == expected


def require_string(payload, key, max_length=200):
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise bad_request("'{}' is required.".format(key))
    value = value.strip()
    if len(value) > max_length:
        raise bad_request("'{}' is too long.".format(key))
    return value
