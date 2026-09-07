#!/usr/bin/env python3
"""Smoke-test the deployed hello API two ways:

  1. Invoke the Lambda function directly via boto3 — isolates bugs in the
     function code itself, independent of API Gateway.
  2. Call the deployed HTTPS endpoint — exercises the full path from the
     architecture diagram (Postman/browser -> API Gateway -> Lambda).

If (1) fails, the bug is in the Lambda handler. If (1) passes but (2) fails,
the bug is in the API Gateway configuration (method, integration, permission,
or deployment/stage).

The endpoint echoes back any query string parameters in the response body
under "params", so this also verifies that round-trip: it calls the direct
invoke with no params (expects "params": {}) and the HTTP endpoint with
?name=CS218 (expects "params": {"name": "CS218"}).

Usage:
    python scripts/smoke_test.py --invoke-url "$(terraform -chdir=infra output -raw invoke_url)"
"""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

import boto3

FUNCTION_NAME = "hello-function"


def test_direct_invoke(region: str) -> bool:
    print("1. Invoking Lambda function directly via boto3 (no params)...")
    client = boto3.client("lambda", region_name=region)
    response = client.invoke(FunctionName=FUNCTION_NAME, Payload=b"{}")
    payload = json.loads(response["Payload"].read())
    body = json.loads(payload.get("body", "{}"))

    if payload.get("statusCode") == 200 and body == {"message": "Hello", "params": {}}:
        print(f"   PASS - {body}")
        return True
    print(f"   FAIL - got {payload}")
    return False


def test_http_call(invoke_url: str) -> bool:
    url = invoke_url + "?" + urllib.parse.urlencode({"name": "CS218"})
    print(f"2. Calling deployed endpoint: {url}")
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            status = resp.status
            body = json.loads(resp.read())
    except urllib.error.URLError as exc:
        print(f"   FAIL - request error: {exc}")
        return False

    expected = {"message": "Hello", "params": {"name": "CS218"}}
    if status == 200 and body == expected:
        print(f"   PASS - {body}")
        return True
    print(f"   FAIL - status={status} body={body}")
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--invoke-url",
        required=True,
        help="Full https://.../hello URL, e.g. from `terraform output invoke_url`",
    )
    parser.add_argument("--region", default="us-east-1", help="AWS region of the deployed function")
    args = parser.parse_args()

    results = [
        test_direct_invoke(args.region),
        test_http_call(args.invoke_url),
    ]

    if all(results):
        print("\nAll checks passed.")
        sys.exit(0)
    print("\nSome checks failed.")
    sys.exit(1)


if __name__ == "__main__":
    main()
