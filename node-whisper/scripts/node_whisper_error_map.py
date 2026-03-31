#!/usr/bin/env python3
import argparse
import json
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True)
    parser.add_argument("--error-code", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--details")
    parser.add_argument("--exit-code", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = {
        "ok": False,
        "stage": args.stage,
        "error_code": args.error_code,
        "message": args.message,
    }

    if args.details:
        try:
            payload["details"] = json.loads(args.details)
        except json.JSONDecodeError:
            payload["details"] = {"raw": args.details}

    print(json.dumps(payload, ensure_ascii=False))
    return args.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
