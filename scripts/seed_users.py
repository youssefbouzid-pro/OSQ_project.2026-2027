#!/usr/bin/env python3
"""Seed personal access tokens into the ``users`` table.

Implements the token issuance rules in docs/16:

1. A random token is generated per seeded user.
2. Only the SHA-256 hash is written, as ``users.tokenHash``.
3. The plaintext token is printed once and must be handed to the learner
   out of band. It is never stored, logged, or written to Git.
4. Revocation is ``isActive = false``.

The script is idempotent: a user that already has a ``tokenHash`` is
left untouched. Pass ``--rotate`` to deliberately replace it.

Usage:

    python scripts/seed_users.py --users-table users
    python scripts/seed_users.py --users-table users --rotate
    python scripts/seed_users.py --users-table users --token-file tokens.txt
"""

import argparse
import os
import secrets
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lambdas"))

from common.auth import hash_token  # noqa: E402
from common.seed_catalog import SEEDED_USERS  # noqa: E402

TOKEN_PREFIX = "cldy_pat_"


def generate_token():
    return TOKEN_PREFIX + secrets.token_urlsafe(24)


def load_token_file(path):
    """Read ``userId=token`` lines so a demo can use fixed tokens."""
    tokens = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            user_id, token = line.split("=", 1)
            tokens[user_id.strip()] = token.strip()
    return tokens


def seed(table, users, tokens=None, rotate=False):
    """Write missing token hashes. Returns (created, rotated, skipped)."""
    tokens = tokens or {}
    created, rotated, skipped = [], [], []

    for template in users:
        user_id = template["userId"]
        existing = table.get_item(Key={"userId": user_id}).get("Item")

        if existing and existing.get("tokenHash") and not rotate:
            skipped.append(user_id)
            continue

        token = tokens.get(user_id) or generate_token()
        record = dict(existing or {})
        record.update(template)
        record["tokenHash"] = hash_token(token)
        table.put_item(Item=record)

        (rotated if existing else created).append((user_id, token))

    return created, rotated, skipped


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--users-table", default=os.environ.get("USERS_TABLE", "users"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    parser.add_argument(
        "--token-file",
        help="Optional file of 'userId=token' lines to use instead of random tokens.",
    )
    parser.add_argument(
        "--rotate",
        action="store_true",
        help="Replace token hashes that already exist. Revokes the old token.",
    )
    args = parser.parse_args(argv)

    import boto3

    table = boto3.resource("dynamodb", region_name=args.region).Table(args.users_table)
    supplied = load_token_file(args.token_file) if args.token_file else {}

    created, rotated, skipped = seed(table, SEEDED_USERS, supplied, args.rotate)

    for user_id, token in created + rotated:
        # Printed once. Nothing here is written to disk.
        print("{}={}".format(user_id, token))

    print("", file=sys.stderr)
    print(
        "seeded: {} created, {} rotated, {} unchanged".format(
            len(created), len(rotated), len(skipped)
        ),
        file=sys.stderr,
    )
    if created or rotated:
        print(
            "These tokens will not be shown again. Give each learner their "
            "own token out of band.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
