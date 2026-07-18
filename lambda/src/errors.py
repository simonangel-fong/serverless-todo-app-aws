"""Typed, client-facing errors and their HTTP status mapping.

The service layer raises these for *expected* failures; the handler catches the
base class and maps to a status in one place, so the same failure class always
yields the same status. Anything not derived from AppError is a genuine bug and
falls through to a last-resort 500 in the handler.
"""


class AppError(Exception):
    """Base for expected, client-facing failures."""


class ValidationError(AppError):
    """Bad or missing input -> 400."""


class NotFoundError(AppError):
    """Item missing, or present but not owned by the caller -> 404."""


_STATUS = {
    ValidationError: 400,
    NotFoundError: 404,
}


def to_status(err):
    """Map a raised error to its HTTP status, defaulting to 500."""
    return _STATUS.get(type(err), 500)
