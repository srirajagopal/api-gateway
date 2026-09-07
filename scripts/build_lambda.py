#!/usr/bin/env python3
"""Package lambda/hello/handler.py into a deployable zip.

`terraform apply` already packages the function automatically via the
`archive_file` data source in infra/lambda.tf, so this script is not required
for a normal deploy. It serves two other purposes:

  1. Inspecting the exact deployment package Terraform builds.
  2. Faster iteration: rebuild the zip and push it straight to an
     already-deployed Lambda function with boto3's `update_function_code`,
     without running a full `terraform apply`.

Usage:
    python scripts/build_lambda.py                # just build infra/hello.zip
    python scripts/build_lambda.py --deploy        # build + push via boto3
"""
import argparse
import pathlib
import zipfile

import boto3

ROOT = pathlib.Path(__file__).resolve().parent.parent
HANDLER_PATH = ROOT / "lambda" / "hello" / "handler.py"
ZIP_PATH = ROOT / "infra" / "hello.zip"
FUNCTION_NAME = "hello-function"


def build_zip() -> pathlib.Path:
    ZIP_PATH.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(HANDLER_PATH, arcname="handler.py")
    print(f"Wrote {ZIP_PATH}")
    return ZIP_PATH


def deploy(zip_path: pathlib.Path, region: str) -> None:
    client = boto3.client("lambda", region_name=region)
    with open(zip_path, "rb") as f:
        client.update_function_code(FunctionName=FUNCTION_NAME, ZipFile=f.read())
    print(f"Updated code for Lambda function '{FUNCTION_NAME}' in {region}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="push the zip straight to the live Lambda function via boto3",
    )
    parser.add_argument("--region", default="us-east-1", help="AWS region of the deployed function")
    args = parser.parse_args()

    zip_path = build_zip()
    if args.deploy:
        deploy(zip_path, args.region)


if __name__ == "__main__":
    main()
