"""Request parsing and response building for API Gateway HTTP API (payload v2)."""

import json


class Request:
    def __init__(self, method, route, path_params, query, headers, body, raw):
        self.method = method
        self.route = route
        self.path_params = path_params or {}
        self.query = query or {}
        self.headers = {str(k).lower(): v for k, v in (headers or {}).items()}
        self.body = body
        self.raw = raw

    @property
    def authorization(self):
        return self.headers.get("authorization", "")

    def json(self):
        """Decode a JSON body, returning {} for an empty one."""
        if not self.body:
            return {}
        if isinstance(self.body, dict):
            return self.body
        try:
            decoded = json.loads(self.body)
        except (ValueError, TypeError):
            raise ValueError("Request body must be valid JSON.")
        if not isinstance(decoded, dict):
            raise ValueError("Request body must be a JSON object.")
        return decoded


def parse_event(event):
    """Normalise an API Gateway HTTP API v2 event into a Request."""
    if not isinstance(event, dict):
        raise ValueError("Unsupported event shape.")

    http = (event.get("requestContext") or {}).get("http") or {}
    method = http.get("method") or event.get("httpMethod") or "GET"
    route_key = event.get("routeKey") or ""
    if not route_key:
        route_key = "{} {}".format(method, event.get("rawPath") or http.get("path") or "/")

    return Request(
        method=method.upper(),
        route=route_key,
        path_params=event.get("pathParameters"),
        query=event.get("queryStringParameters"),
        headers=event.get("headers"),
        body=event.get("body"),
        raw=event,
    )


def _headers(extra=None):
    merged = {"content-type": "application/json"}
    if extra:
        merged.update(extra)
    return merged


def response(status, payload, headers=None):
    return {
        "statusCode": int(status),
        "headers": _headers(headers),
        "body": json.dumps(payload, default=str),
    }


def error_response(status, payload, headers=None):
    return response(status, payload, headers)


def no_content():
    return {"statusCode": 204, "headers": _headers(), "body": ""}
