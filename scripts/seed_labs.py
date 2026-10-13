#!/usr/bin/env python3
"""Load the lab catalog into the ``labs`` table.

Idempotent: lab items are overwritten with the catalog in
``common/seed_catalog.py``, which is the same data the unit tests use.

Usage:

    python scripts/seed_labs.py --labs-table labs
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lambdas"))

from common.seed_catalog import LABS  # noqa: E402


def seed(table, labs=LABS):
    written = []
    for lab in labs:
        table.put_item(Item=lab)
        written.append(lab["labId"])
    return written


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--labs-table", default=os.environ.get("LABS_TABLE", "labs"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    args = parser.parse_args(argv)

    import boto3

    table = boto3.resource("dynamodb", region_name=args.region).Table(args.labs_table)
    written = seed(table)
    print("seeded {} labs: {}".format(len(written), ", ".join(sorted(written))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
