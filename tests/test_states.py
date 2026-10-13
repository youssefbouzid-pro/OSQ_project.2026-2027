"""The canonical state enum must match docs/04 exactly."""

from common import states


def test_enum_values_match_docs_04():
    assert states.ALL_STATES == (
        "REQUESTED",
        "PENDING",
        "PROVISIONING",
        "TAILSCALE_ENROLLMENT",
        "READY",
        "EXPIRING",
        "TERMINATING",
        "TERMINATED",
        "FAILED",
    )


def test_terminal_states():
    assert states.is_terminal(states.TERMINATED)
    assert states.is_terminal(states.FAILED)
    for state in states.ALL_STATES:
        if state not in states.TERMINAL_STATES:
            assert not states.is_terminal(state)


def test_active_states_exclude_terminal_ones():
    assert not states.is_active(states.TERMINATED)
    assert not states.is_active(states.FAILED)
    assert states.is_active(states.READY)
    assert states.is_active(states.EXPIRING)
    assert states.is_active(states.TERMINATING)


def test_terminal_states_cannot_be_reached_from_nowhere():
    # EXPIRING is a derived display state; it is not stored, but it is
    # still part of the enum the API and UI share.
    assert states.EXPIRING in states.ALL_STATES
