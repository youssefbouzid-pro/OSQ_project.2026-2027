"""Error type carried from handlers to the API Gateway response."""


class ApiError(Exception):
    """An error that maps directly to an HTTP status code."""

    def __init__(self, status, message, code=None):
        super().__init__(message)
        self.status = int(status)
        self.message = message
        self.code = code or {
            400: "BAD_REQUEST",
            401: "UNAUTHORIZED",
            403: "FORBIDDEN",
            404: "NOT_FOUND",
            409: "CONFLICT",
            429: "RATE_LIMITED",
        }.get(int(status), "ERROR")

    @property
    def body(self):
        return {"error": self.code, "message": self.message}


def bad_request(message):
    return ApiError(400, message)


def unauthorized(message="Invalid or missing access token."):
    return ApiError(401, message)


def forbidden(message="Your role is not permitted to perform this action."):
    return ApiError(403, message)


def not_found(message="Resource not found."):
    return ApiError(404, message)


def conflict(message):
    return ApiError(409, message)
