"""Make the Lambda package importable from the repo root."""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAMBDAS = os.path.join(ROOT, "lambdas")
SCRIPTS = os.path.join(ROOT, "scripts")

for path in (LAMBDAS, SCRIPTS):
    if path not in sys.path:
        sys.path.insert(0, path)
