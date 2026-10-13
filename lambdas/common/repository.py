"""Data access for the four DynamoDB tables in docs/16.

Two implementations share this interface:

* :class:`Repository` - talks to DynamoDB through boto3.
* :class:`MemoryRepository` - an in-memory stand-in used by unit tests.

Handlers only ever see the interface, so the HTTP layer can be tested
end-to-end without AWS.

GSI note: ``docs/16`` specifies primary keys only. Two access patterns
need indexes and neither changes the documented attributes:

* ``users`` is looked up by ``tokenHash`` on every request, so it carries
  the ``by-token-hash`` index.
* ``sessions`` is listed per learner, so it carries the ``by-user``
  index (``userId`` hash, ``createdAt`` range).
"""

from boto3.dynamodb.conditions import Key

from . import activity as events
from . import states

USER_TOKEN_INDEX = "by-token-hash"
SESSION_USER_INDEX = "by-user"

#: Attributes that are always updated together when a session moves state.
SESSION_STATE_FIELDS = ("state", "endedAt", "terminationReason", "errorMessage")


class Repository:
    """DynamoDB-backed implementation."""

    def __init__(self, users, labs, sessions, activity):
        self.users = users
        self.labs = labs
        self.sessions = sessions
        self.activity = activity

    # -- users ---------------------------------------------------------

    def find_user_by_token_hash(self, token_hash):
        if not token_hash:
            return None
        response = self.users.query(
            IndexName=USER_TOKEN_INDEX,
            KeyConditionExpression=Key("tokenHash").eq(token_hash),
            Limit=1,
            ConsistentRead=False,
        )
        items = response.get("Items") or []
        return items[0] if items else None

    def get_user(self, user_id):
        response = self.users.get_item(Key={"userId": user_id})
        return response.get("Item")

    def put_user(self, user):
        self.users.put_item(Item=user)
        return user

    def list_users(self):
        items = []
        response = self.users.scan()
        items.extend(response.get("Items") or [])
        while response.get("LastEvaluatedKey"):
            response = self.users.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
            items.extend(response.get("Items") or [])
        return items

    # -- labs ----------------------------------------------------------

    def get_lab(self, lab_id):
        response = self.labs.get_item(Key={"labId": lab_id})
        return response.get("Item")

    def put_lab(self, lab):
        self.labs.put_item(Item=lab)
        return lab

    def list_labs(self):
        items = []
        response = self.labs.scan()
        items.extend(response.get("Items") or [])
        while response.get("LastEvaluatedKey"):
            response = self.labs.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
            items.extend(response.get("Items") or [])
        return items

    # -- sessions ------------------------------------------------------

    def get_session(self, session_id):
        response = self.sessions.get_item(Key={"sessionId": session_id})
        return response.get("Item")

    def put_session(self, session):
        self.sessions.put_item(Item=session)
        return session

    def update_session(self, session_id, **attrs):
        """Partial update. Only the provided attributes are written, so a
        concurrent writer cannot clobber fields this call did not touch."""
        if not attrs:
            return self.get_session(session_id)

        names = {}
        values = {}
        assignments = []
        for index, (attr, value) in enumerate(sorted(attrs.items())):
            placeholder = "#{}".format(index)
            value_placeholder = ":{}".format(index)
            names[placeholder] = attr
            values[value_placeholder] = value
            assignments.append("{} = {}".format(placeholder, value_placeholder))

        self.sessions.update_item(
            Key={"sessionId": session_id},
            UpdateExpression="SET " + ", ".join(assignments),
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
        )
        return self.get_session(session_id)

    def list_sessions_for_user(self, user_id):
        response = self.sessions.query(
            IndexName=SESSION_USER_INDEX,
            KeyConditionExpression=Key("userId").eq(user_id),
            ScanIndexForward=False,
        )
        return list(response.get("Items") or [])

    def list_sessions(self, limit=None):
        items = []
        response = self.sessions.scan()
        items.extend(response.get("Items") or [])
        while (limit is None or len(items) < limit) and response.get(
            "LastEvaluatedKey"
        ):
            response = self.sessions.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            items.extend(response.get("Items") or [])
        items.sort(key=lambda s: s.get("createdAt", ""), reverse=True)
        return items[:limit] if limit else items

    def active_sessions_for_user(self, user_id):
        return [s for s in self.list_sessions_for_user(user_id) if states.is_active(s.get("state"))]

    def count_active_for_user(self, user_id):
        return len(self.active_sessions_for_user(user_id))

    def count_active_platform(self):
        return len([s for s in self.list_sessions() if states.is_active(s.get("state"))])

    def list_expired_sessions(self, now_iso):
        """Active sessions whose TTL has passed. Drives the GC fallback."""
        expired = []
        for session in self.list_sessions():
            if not states.is_active(session.get("state")):
                continue
            expires_at = session.get("expiresAt") or ""
            if expires_at and expires_at <= now_iso:
                expired.append(session)
        return expired

    # -- activity ------------------------------------------------------

    def put_event(self, event):
        self.activity.put_item(Item=event)
        return event

    def list_events(self, limit=100):
        items = []
        response = self.activity.scan()
        items.extend(response.get("Items") or [])
        while response.get("LastEvaluatedKey"):
            response = self.activity.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            items.extend(response.get("Items") or [])
        items.sort(key=lambda e: e.get("at", ""), reverse=True)
        return items[:limit]


class MemoryRepository(Repository):
    """Drop-in replacement backed by dicts. Used by the unit tests."""

    class _Table:
        def __init__(self, key_name):
            self.key_name = key_name
            self.items = {}

        def get_item(self, Key):
            item = self.items.get(Key[self.key_name])
            return {"Item": dict(item)} if item is not None else {}

        def put_item(self, Item):
            self.items[Item[self.key_name]] = dict(Item)
            return {}

        def scan(self, ExclusiveStartKey=None, **_):
            keys = sorted(self.items)
            if ExclusiveStartKey is not None:
                start = keys.index(ExclusiveStartKey[self.key_name]) + 1
                keys = keys[start:]
            return {"Items": [dict(self.items[k]) for k in keys]}

        def query(self, **_):
            raise NotImplementedError(
                "MemoryRepository overrides every GSI query; add an override "
                "for any new access pattern."
            )

        def update_item(self, Key, UpdateExpression=None, ExpressionAttributeNames=None,
                        ExpressionAttributeValues=None, **_):
            item = self.items.get(Key[self.key_name])
            if item is None:
                raise KeyError("Item not found: {}".format(Key))
            for name_placeholder, attr in (ExpressionAttributeNames or {}).items():
                value_placeholder = ":" + name_placeholder.lstrip("#")
                if value_placeholder in (ExpressionAttributeValues or {}):
                    item[attr] = ExpressionAttributeValues[value_placeholder]
            return {}

    def __init__(self):
        super().__init__(
            users=self._Table("userId"),
            labs=self._Table("labId"),
            sessions=self._Table("sessionId"),
            activity=self._Table("eventId"),
        )

    def find_user_by_token_hash(self, token_hash):
        for user in self.users.items.values():
            if user.get("tokenHash") == token_hash:
                return dict(user)
        return None

    def list_sessions_for_user(self, user_id):
        matched = [s for s in self.sessions.items.values() if s.get("userId") == user_id]
        matched.sort(key=lambda s: s.get("createdAt", ""), reverse=True)
        return [dict(s) for s in matched]
