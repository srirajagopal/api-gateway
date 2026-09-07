#!/usr/bin/env python3
"""Confirm nothing from this project is still running after `terraform destroy`.

This does not delete anything — `terraform destroy` (run from infra/) is the
actual teardown step. This script just checks, via boto3, that the Lambda
function, REST API, and IAM role are all gone, so you can be sure nothing is
left behind (and possibly billing) in your account.

Usage:
    python scripts/verify_teardown.py --region us-east-1
"""
import argparse
import sys

import boto3
from botocore.exceptions import ClientError

FUNCTION_NAME = "hello-function"
API_NAME = "hello-api"
ROLE_NAME = "hello-lambda-exec-role"


def check_lambda(region: str) -> bool:
    client = boto3.client("lambda", region_name=region)
    try:
        client.get_function(FunctionName=FUNCTION_NAME)
        print(f"STILL EXISTS - Lambda function '{FUNCTION_NAME}'")
        return False
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ResourceNotFoundException":
            print(f"gone - Lambda function '{FUNCTION_NAME}'")
            return True
        raise


def check_rest_api(region: str) -> bool:
    client = boto3.client("apigateway", region_name=region)
    paginator = client.get_paginator("get_rest_apis")
    for page in paginator.paginate():
        for api in page["items"]:
            if api["name"] == API_NAME:
                print(f"STILL EXISTS - REST API '{API_NAME}' (id={api['id']})")
                return False
    print(f"gone - REST API '{API_NAME}'")
    return True


def check_iam_role(region: str) -> bool:
    client = boto3.client("iam", region_name=region)
    try:
        client.get_role(RoleName=ROLE_NAME)
        print(f"STILL EXISTS - IAM role '{ROLE_NAME}'")
        return False
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "NoSuchEntity":
            print(f"gone - IAM role '{ROLE_NAME}'")
            return True
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--region", default="us-east-1", help="AWS region the resources were deployed in")
    args = parser.parse_args()

    results = [
        check_lambda(args.region),
        check_rest_api(args.region),
        check_iam_role(args.region),
    ]

    if all(results):
        print("\nTeardown complete - nothing left behind.")
        sys.exit(0)
    print("\nSomething is still around - re-run `terraform destroy` in infra/.")
    sys.exit(1)


if __name__ == "__main__":
    main()
