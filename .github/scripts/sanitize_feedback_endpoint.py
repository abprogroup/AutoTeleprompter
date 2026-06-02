import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


BLOCKED_QUERY_KEYS = {
    "token",
    "access_token",
    "api_key",
    "apikey",
    "key",
    "secret",
    "client_secret",
    "auth",
}


def sanitize_feedback_endpoint(raw_value: str) -> str:
    value = raw_value.replace("\r", "").replace("\n", "").strip()
    if not value:
        return ""

    parts = urlsplit(value)
    query = parse_qsl(parts.query, keep_blank_values=True)
    clean_query = [
        (key, val)
        for key, val in query
        if key.lower() not in BLOCKED_QUERY_KEYS
    ]
    if len(clean_query) == len(query):
        return value

    return urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path,
            urlencode(clean_query),
            parts.fragment,
        )
    )


if __name__ == "__main__":
    print(sanitize_feedback_endpoint(sys.argv[1] if len(sys.argv) > 1 else ""))
