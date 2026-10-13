"""Token authentication.

There is no login endpoint (``docs/16``). A personal access token is
presented as ``Authorization: Bearer <token>``, hashed with SHA-256, and
looked up in the ``users`` table by ``tokenHash``.

The plaintext token is never stored, logged, or echoed back.
"""

import hashlib

from .errors import forbidden, unauthorized

ROLE_STUDENT = "student"
ROLE_ADMIN = "admin"
ROLE_AUDITOR = "auditor"
ROLES = (ROLE_STUDENT, ROLE_ADMIN, ROLE_AUDITOR)

AUTH_SCHEME = "bearer "


def hash_token(token):
    """SHA-256 hex digest of a token, as stored in ``users.tokenHash``."""
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def extract_token(authorization_header):
    """Pull the raw token out of an Authorization header value."""
    if not authorization_header:
        return None
    value = authorization_header.strip()
    if value.lower().startswith(AUTH_SCHEME):
        value = value[len(AUTH_SCHEME):].strip()
    elif value.lower().startswith("token "):
        value = value[6:].strip()
    if not value:
        return None
    return value


def authenticate(repo, authorization_header):
    """Resolve an Authorization header to an active user record.

    Raises ``ApiError(401)`` when the token is missing, unknown, or
    belongs to a revoked user.
    """
    token = extract_token(authorization_header)
    if not token:
        raise unauthorized("Missing 'Authorization: Bearer <token>' header.")

    user = repo.find_user_by_token_hash(hash_token(token))
    if not user:
        raise unauthorized("Invalid access token.")
    if not user.get("isActive", False):
        raise unauthorized("This access token has been revoked.")
    if user.get("role") not in ROLES:
        raise unauthorized("User has no assigned role.")
    return user


def require_roles(user, *roles):
    """Raise ``ApiError(403)`` unless the user holds one of ``roles``."""
    if user.get("role") not in roles:
        raise forbidden()
    return user
