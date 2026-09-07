# Simple API Gateway → Lambda "Hello" — Terraform + boto3 Plan

---

## 1. Project Summary

A REST API exposes `GET /hello`, backed by a single Lambda function that
returns a JSON message and echoes back any query string parameters on the
request.

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
  "message": "Hello",
  "params": {}
}
```

`params` holds whatever query string parameters were on the request (empty
object if none), e.g. `GET /hello?name=CS218` returns
`{"message": "Hello", "params": {"name": "CS218"}}`. Returned with
`Content-Type: application/json` and HTTP 200. Path params and request body
are not read.

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
├── README.md
├── LICENSE
├── .gitignore                root-level, Terraform + Python + OS patterns
├── infra/
│   ├── providers.tf          AWS provider + region
│   ├── variables.tf          aws_region, stage_name
│   ├── lambda.tf             IAM role, Lambda function resource
│   ├── api.tf                REST API, /hello resource, GET method, integration,
│   │                         Lambda permission, deployment, stage
│   ├── outputs.tf            invoke_url, lambda_function_name, rest_api_id
│   ├── terraform.tfvars.example
│   └── .terraform.lock.hcl   committed, pins provider versions
├── lambda/
│   └── hello/
│       └── handler.py        Lambda function source
└── scripts/
    ├── requirements.txt
    ├── build_lambda.py       zip handler.py; optionally push via boto3 update_function_code
    ├── smoke_test.py         call the deployed endpoint via direct invoke + HTTPS, assert response
    └── verify_teardown.py    confirm Lambda/API/IAM role are gone after terraform destroy
```

Terraform owns all AWS resource state. boto3 covers what Terraform doesn't:
zipping Lambda source into a deployment package, and calling the live
endpoint over HTTP the way a client would.

---

## 4. Lambda Function

`lambda/hello/handler.py`:

```python
import json


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Hello", "params": params}),
    }
```

Runtime: `python3.12`. No third-party dependencies, so the deployment package
is just the zipped source file — no `pip install -t` vendoring step needed.
`event["queryStringParameters"]` is populated directly by the API Gateway
`AWS_PROXY` integration; no Terraform configuration is required to pass query
parameters through.

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
| `aws_api_gateway_stage` | Publishes the deployment under a stage, e.g. `prod` (`var.stage_name`) |

`outputs.tf` exposes `invoke_url` = `https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/hello`,
so `terraform output invoke_url` feeds directly into `smoke_test.py` and into
Postman.

The `archive_file` data source in `lambda.tf` produces `hello.zip` from
`lambda/hello/handler.py` automatically on `terraform plan`/`apply` —
`aws_lambda_function` references it via `filename` + `source_code_hash`, so
editing the handler and re-running `terraform apply` is enough to redeploy.

---

## 6. boto3 Scripts

### `scripts/build_lambda.py`
Zips `lambda/hello/handler.py` into `infra/hello.zip` with Python's `zipfile`
module. Not required for a normal `terraform apply`, since Terraform packages
the function itself; useful for inspecting the exact deployment package, or
for pushing a handler change straight to the live function with `--deploy`
(boto3 `update_function_code`) without a full `terraform apply`.

### `scripts/smoke_test.py`
Checks the deployed API two ways:
1. **Direct Lambda invoke**, no query params — `boto3.client("lambda").invoke(...)`,
   asserts `{"message": "Hello", "params": {}}`. Confirms the function itself
   works, independent of API Gateway.
2. **HTTP call through the deployed stage**, `?name=CS218` — `urllib.request`
   against `terraform output invoke_url`, asserts
   `{"message": "Hello", "params": {"name": "CS218"}}`. Confirms the full
   path from the diagram, API Gateway included.

If (1) fails, the bug is in the Lambda handler. If (1) passes and (2) fails,
the bug is in the API Gateway integration/permission/deployment.

### `scripts/verify_teardown.py`
Read-only check, run after `terraform destroy`: confirms the Lambda function,
REST API, and IAM role no longer exist via boto3. Does not delete anything.

---

## 7. Build & Deploy Steps

```bash
cd api-gateway/infra
cp terraform.tfvars.example terraform.tfvars   # set aws_region
terraform init
terraform apply

terraform output invoke_url
curl "$(terraform output -raw invoke_url)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}

python ../scripts/smoke_test.py --invoke-url "$(terraform output -raw invoke_url)"
```

Manual verification alternative: a Postman `GET` request to the same URL,
with `name=CS218` under the Params tab.

---

## 8. Teardown

```bash
cd infra
terraform destroy
python ../scripts/verify_teardown.py --region us-east-1
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
| `terraform apply` doesn't pick up handler code changes | `source_code_hash` not wired to the zip's hash |
