# Simple API Gateway → Lambda "Hello" — Terraform + boto3 Plan

**Format:** Terraform for infrastructure, boto3 for build/deploy/test automation, AWS Free Tier–oriented

---

## 1. Project Summary

A minimal serverless HTTP endpoint: a REST API exposes `GET /hello`, backed by
a single Lambda function that returns a static JSON message. No datastore, no
auth, no event triggers — this is the smallest possible API Gateway + Lambda
integration.

```
                           HTTPS
Postman / Browser ──────────────────────► API Gateway
                                           REST API
                                              │
                                         GET /hello
                                              │
                                              ▼
                                        AWS Lambda
                                              │
                                              ▼
                                     {"message":"Hello"}
```

### Response contract

```json
{
  "message": "Hello"
}
```

Returned with `Content-Type: application/json` and HTTP 200 for any `GET
/hello` request. No request body, path params, or query params are read.

---

## 2. Prerequisites

1. **AWS account + region.** Any region works; pick one and use it
   consistently across the Terraform provider block and every boto3 client
   (e.g. `us-east-1`).
2. **IAM user, not root**, with programmatic access (`aws configure`) and
   permissions for: `lambda:*`, `apigateway:*`, `iam:CreateRole` /
   `iam:PutRolePolicy` / `iam:PassRole`, `logs:*` (for CloudWatch Logs).
3. **Tooling:**
   ```bash
   pip install boto3
   terraform -version   # >= 1.5
   aws configure
   ```
4. **Free Tier note.** Lambda (1M requests/month) is Always Free. API Gateway
   REST API (1M calls/month) is free only within an account's 12-month
   new-customer window — verify current terms rather than assuming this.
   At the volume this project generates (a handful of manual test calls),
   cost is effectively zero either way.

---

## 3. Repository Layout

```
api-gateway/
├── Plan.md                  (this file)
├── infra/
│   ├── providers.tf         AWS provider + region
│   ├── lambda.tf            IAM role, Lambda function resource
│   ├── api.tf               REST API, /hello resource, GET method, integration,
│   │                        Lambda permission, deployment, stage
│   ├── outputs.tf           invoke_url output
│   └── terraform.tfvars.example
├── lambda/
│   └── hello/
│       └── handler.py       Lambda function source
└── scripts/
    ├── build_lambda.py      boto3/zipfile: package handler.py into hello.zip
    └── smoke_test.py        boto3/requests: call the deployed endpoint, assert response
```

Terraform owns all AWS resource state. boto3 is used only for the two things
Terraform is a poor fit for: zipping Lambda source into a deployment package,
and exercising the live endpoint end-to-end as a client would.

---

## 4. Lambda Function

`lambda/hello/handler.py`:

```python
import json

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Hello"}),
    }
```

Runtime: `python3.12`. No third-party dependencies, so the deployment package
is just the zipped source file — no `pip install -t` vendoring step needed.

---

## 5. Terraform Resources

| Resource | Purpose |
|---|---|
| `aws_iam_role` (lambda exec role) | Trust policy allowing `lambda.amazonaws.com` to assume it |
| `aws_iam_role_policy_attachment` | Attach `AWSLambdaBasicExecutionRole` (CloudWatch Logs write access) |
| `aws_lambda_function` | Deploys `hello.zip`, handler `handler.handler`, runtime `python3.12` |
| `aws_api_gateway_rest_api` | The REST API container (`hello-api`) |
| `aws_api_gateway_resource` | Adds the `/hello` path under the API's root |
| `aws_api_gateway_method` | `GET` on `/hello`, `authorization = "NONE"` |
| `aws_api_gateway_integration` | `AWS_PROXY` integration from the method to the Lambda function |
| `aws_lambda_permission` | Grants API Gateway's execution ARN permission to invoke the Lambda |
| `aws_api_gateway_deployment` | Deploys the API configuration |
| `aws_api_gateway_stage` | Publishes the deployment under a stage, e.g. `prod` |

`outputs.tf` exposes `invoke_url` = `https://<api-id>.execute-api.<region>.amazonaws.com/prod/hello`,
so `terraform output invoke_url` feeds directly into `smoke_test.py` and into
Postman.

Use `data "archive_file"` (or the `build_lambda.py` boto3 script below) to
produce `hello.zip` from `lambda/hello/handler.py` before `aws_lambda_function`
references it via `filename` + `source_code_hash`.

---

## 6. boto3 Scripts

### `scripts/build_lambda.py`
Zips `lambda/hello/handler.py` into `infra/hello.zip` using Python's
`zipfile` module (boto3 isn't strictly required here, but the script lives
alongside the other automation for a single "run this before `terraform
apply`" step). Run before every `terraform apply` that changes the handler.

### `scripts/smoke_test.py`
Uses `boto3` to check the deployed API two ways:
1. **Direct Lambda invoke** — `boto3.client("lambda").invoke(FunctionName=...,
   Payload=...)` — confirms the function itself works, independent of API
   Gateway.
2. **HTTP call through the deployed stage** — plain `urllib.request` (or
   `requests` if available) against `terraform output invoke_url`, asserting
   HTTP 200 and `{"message": "Hello"}` — confirms the full path from the
   diagram, API Gateway included.

Both checks failing narrows the problem to Lambda; only the second failing
narrows it to the API Gateway integration/permission/deployment.

---

## 7. Build & Deploy Steps

```bash
cd api-gateway
python scripts/build_lambda.py          # produces infra/hello.zip

cd infra
cp terraform.tfvars.example terraform.tfvars   # set aws_region
terraform init
terraform apply

terraform output invoke_url
python ../scripts/smoke_test.py          # exercises Lambda directly and via HTTPS
```

Manual verification alternatives: `curl <invoke_url>` or a Postman `GET`
request to the same URL — both should return `{"message":"Hello"}`.

---

## 8. Teardown

```bash
cd infra
terraform destroy
```

No persistent state (no S3 bucket, no DynamoDB table) exists outside
Terraform state, so `terraform destroy` fully removes all billable resources.

---

## 9. Common Failure Modes

| Symptom | Likely cause |
|---|---|
| `403 Forbidden` calling the invoke URL | Missing/incorrect `aws_lambda_permission` source ARN, or stage not deployed after a resource change |
| `502 Bad Gateway` | Lambda handler path wrong (`handler.handler` mismatch) or handler throws before returning a valid `statusCode`/`body` shape |
| Direct Lambda invoke works, HTTP call fails | Problem is in API Gateway config (integration type, method, deployment/stage), not the function |
| `terraform apply` doesn't pick up handler code changes | `source_code_hash` not wired to the zip's hash, or `build_lambda.py` wasn't re-run before `apply` |
