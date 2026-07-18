"""Test setup: make src/ importable and keep tests hermetic (no real AWS).

The src modules import each other flatly (`import service`, `import repository`)
because in the Lambda runtime the handler sits at the package root. We replicate
that by putting src/ on sys.path. `repository` calls boto3 at import time, so we
stub boto3 before it's imported — service tests inject a FakeRepo and never hit
the real client anyway.
"""

import os
import sys
import types

SRC = os.path.join(os.path.dirname(__file__), "..", "src")
sys.path.insert(0, os.path.abspath(SRC))

# Stub boto3 so `import repository` succeeds without AWS credentials/network.
if "boto3" not in sys.modules:
    boto3_stub = types.ModuleType("boto3")

    class _StubTable:
        def __getattr__(self, _name):
            raise AssertionError(
                "Real DynamoDB called in a unit test — inject a FakeRepo instead."
            )

    class _StubResource:
        def Table(self, _name):
            return _StubTable()

    boto3_stub.resource = lambda *_a, **_k: _StubResource()
    boto3_stub.client = lambda *_a, **_k: _StubTable()
    sys.modules["boto3"] = boto3_stub

    # boto3.dynamodb.conditions.Key used by repository at import time.
    dynamodb_mod = types.ModuleType("boto3.dynamodb")
    conditions_mod = types.ModuleType("boto3.dynamodb.conditions")

    class _Key:
        def __init__(self, name):
            self.name = name

        def eq(self, value):
            return (self.name, "eq", value)

    conditions_mod.Key = _Key
    dynamodb_mod.conditions = conditions_mod
    sys.modules["boto3.dynamodb"] = dynamodb_mod
    sys.modules["boto3.dynamodb.conditions"] = conditions_mod
