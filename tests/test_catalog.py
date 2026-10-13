"""Flag redaction. docs/16: expectedFlag must never reach a client."""

import json

from common import catalog as cat
from common.seed_catalog import LABS, labs_by_id


def test_redact_task_strips_expected_flag():
    task = labs_by_id()["linux-beginner"]["tasks"][0]
    assert task["expectedFlag"] == "CB-LINUX-B-01"
    clean = cat.redact_task(task)
    assert "expectedFlag" not in clean
    assert clean["taskId"] == "linux-b-1"
    assert clean["title"] == task["title"]


def test_redact_lab_strips_every_task():
    clean = cat.redact_lab(labs_by_id()["linux-beginner"])
    assert "expectedFlag" not in json.dumps(clean)
    assert len(clean["tasks"]) == 2


def test_public_lab_can_drop_tasks_entirely():
    clean = cat.public_lab(labs_by_id()["dba-beginner"], include_tasks=False)
    assert "tasks" not in clean
    assert "expectedFlag" not in json.dumps(clean)


def test_normalize_flag_trims_and_uppercases():
    assert cat.normalize_flag("  cb-linux-b-01  ") == "CB-LINUX-B-01"
    assert cat.normalize_flag(None) == ""
    assert cat.normalize_flag(12345) == ""


def test_matches_flag():
    task = {"expectedFlag": "cb-linux-b-01"}
    assert cat.matches_flag(task, "CB-LINUX-B-01")
    assert cat.matches_flag(task, "  cb-linux-b-01 ")
    assert not cat.matches_flag(task, "CB-LINUX-B-02")
    assert not cat.matches_flag(task, "")


def test_task_without_an_answer_can_never_be_accepted():
    assert not cat.matches_flag({"taskId": "x"}, "CB-ANYTHING")


def test_every_seeded_lab_has_answers_and_approved_types():
    approved = {"t4g.micro", "t4g.small", "t4g.medium"}
    for lab in LABS:
        assert lab["instanceType"] in approved, lab["labId"]
        assert lab["amiParameter"].startswith("/cloudybt/ami/")
        assert lab["ttlMinutes"] == 60
        assert lab["tasks"], lab["labId"]
        for task in lab["tasks"]:
            assert task["expectedFlag"], (lab["labId"], task["taskId"])
