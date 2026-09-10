#!/usr/bin/env python3
import base64
import json
import os
import sys
import tempfile

import firebase_admin
from firebase_admin import credentials, messaging


def parse_data(raw: str):
    raw = raw.strip()
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as error:
        print(f"::error::data is not valid JSON: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    if not isinstance(parsed, dict):
        print("::error::data must be a JSON object.", file=sys.stderr)
        raise SystemExit(1)
    return {str(key): str(value) for key, value in parsed.items()}


def main() -> None:
    if len(sys.argv) not in (4, 5):
        print(
            "Usage: notify_push.py <topic> <title> <body> [data-json]",
            file=sys.stderr,
        )
        raise SystemExit(2)

    topic, title, body = sys.argv[1], sys.argv[2], sys.argv[3]
    data = parse_data(sys.argv[4] if len(sys.argv) == 5 else "")

    encoded = os.environ.get("FCM_SERVICE_ACCOUNT_BASE64", "")
    if not encoded:
        print("::error::FCM_SERVICE_ACCOUNT_BASE64 is not configured.", file=sys.stderr)
        raise SystemExit(1)

    with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as key_file:
        key_file.write(base64.b64decode(encoded))
        key_path = key_file.name

    try:
        firebase_admin.initialize_app(credentials.Certificate(key_path))
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data,
            topic=topic,
        )
        print("sent:", messaging.send(message))
    finally:
        os.unlink(key_path)


if __name__ == "__main__":
    main()
