# Simple API Gateway → Lambda "Hello"

Reference implementation of the plan in [`Plan.md`](Plan.md). A REST API
exposes `GET /hello`, backed by a single Lambda function that returns
`{"message":"Hello"}`.

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

## Repository layout

```
infra/      Terraform root — IAM role, Lambda function, REST API, deployment/stage
lambda/     Lambda function source (hello/handler.py)
scripts/    boto3 helper scripts, run from the command line, not deployed
```

`terraform apply` packages `lambda/hello/handler.py` into a zip automatically
(via the `archive_file` data source in `infra/lambda.tf`) — you do not need to
run anything by hand before the first deploy.

## 1. Prerequisites

- An AWS account and an IAM user (not root) with programmatic access keys.
  The user needs permission to create/manage: Lambda functions, IAM roles,
  API Gateway REST APIs, and CloudWatch Logs. For a personal account,
  attaching `AdministratorAccess` to this IAM user is the simplest option;
  for a shared account, use an IAM policy scoped to just those permissions
  instead.
- Terraform >= 1.5 ([install guide](https://developer.hashicorp.com/terraform/install))
- Python 3.9+ and `pip`
- AWS CLI (optional but convenient): `pip install awscli`

Configure your credentials once, in the region you intend to use throughout:

```bash
aws configure
# AWS Access Key ID / Secret Access Key / region (e.g. us-east-1) / output format
```

Verify the CLI can see your account before touching Terraform:

```bash
aws sts get-caller-identity
```

## 2. Install Python dependencies for the helper scripts

```bash
cd scripts
pip install -r requirements.txt
cd ..
```

## 3. Deploy the infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if you want a region other than us-east-1

terraform init
terraform plan     # review what will be created
terraform apply    # type "yes" to confirm
```

This creates, in order: an IAM role for the Lambda function, the Lambda
function itself (zipped from `lambda/hello/handler.py`), a REST API with a
`/hello` resource and `GET` method, a `AWS_PROXY` integration to the Lambda
function, the permission letting API Gateway invoke it, and a deployment
published under the `prod` stage.

When it finishes, note the output:

```bash
terraform output invoke_url
# https://<api-id>.execute-api.<region>.amazonaws.com/prod/hello
```

## 4. Test it against your AWS account

**Quickest check — curl or a browser:**

```bash
curl "$(terraform -chdir=infra output -raw invoke_url)"
# {"message": "Hello", "params": {}}

curl "$(terraform -chdir=infra output -raw invoke_url)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}
```

Any query string parameters on the request are echoed back under `params` —
the handler reads them straight out of the proxy-integration `event`
(`event["queryStringParameters"]`), so no Terraform changes are needed to add
more of them later.

**Postman:** create a new `GET` request, paste in the `invoke_url` value, add
a query param (e.g. `name=CS218`) under the Params tab, and hit Send. You
should get HTTP `200` and a JSON body echoing that param back.

**Automated smoke test (boto3):** runs two checks — a direct Lambda invoke
with no params (bypasses API Gateway entirely) and an HTTPS call with
`?name=CS218` through the deployed stage (exercises the full path in the
diagram above). If the first passes and the second fails, the bug is in the
API Gateway configuration, not the function.

```bash
cd scripts
python smoke_test.py --invoke-url "$(terraform -chdir=../infra output -raw invoke_url)" --region us-east-1
```

Expected output:

```
1. Invoking Lambda function directly via boto3 (no params)...
   PASS - {'message': 'Hello', 'params': {}}
2. Calling deployed endpoint: https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/hello?name=CS218
   PASS - {'message': 'Hello', 'params': {'name': 'CS218'}}

All checks passed.
```

## 5. Iterating on the Lambda code

`terraform apply` re-zips and redeploys automatically whenever
`lambda/hello/handler.py` changes (Terraform detects the change via
`source_code_hash`). For faster iteration without a full `terraform apply`,
you can push code changes straight to the live function with boto3:

```bash
cd scripts
python build_lambda.py --deploy --region us-east-1
```

## 6. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `403 Forbidden` calling the invoke URL | Missing/incorrect Lambda permission, or the API wasn't redeployed after a resource change — re-run `terraform apply` |
| `502 Bad Gateway` | Lambda handler throws, or the handler path (`handler.handler`) doesn't match the file/function name |
| Direct Lambda invoke passes, HTTP call fails | The bug is in API Gateway (method, integration, permission, or stage), not the function |
| `terraform apply` doesn't pick up a handler code change | Confirm you edited `lambda/hello/handler.py` and re-ran `terraform apply` — `source_code_hash` should trigger a redeploy automatically |
| `AccessDenied` during `terraform apply` | The IAM user configured in `aws configure` lacks permission for one of: `lambda:*`, `apigateway:*`, `iam:CreateRole`/`PutRolePolicy`/`PassRole`, `logs:*` |

## 7. Tear down

Remove every resource this project created so nothing keeps running in your
account:

```bash
cd infra
terraform destroy   # type "yes" to confirm
```

There's no S3 bucket or database involved, so `terraform destroy` fully
cleans up — no manual console steps needed afterward.

**Optional — confirm nothing was left behind.** This doesn't delete
anything; it just checks via boto3 that the Lambda function, REST API, and
IAM role are all gone:

```bash
cd scripts
python verify_teardown.py --region us-east-1
```

```
gone - Lambda function 'hello-function'
gone - REST API 'hello-api'
gone - IAM role 'hello-lambda-exec-role'

Teardown complete - nothing left behind.
```

If anything reports `STILL EXISTS`, re-run `terraform destroy` from `infra/`
— the state file still knows about it.

## Cost

Lambda (1M requests/month) is part of AWS's Always Free tier. API Gateway
REST API (1M calls/month) is free only within an account's 12-month
new-customer window. At the handful of manual/smoke-test calls this project
generates, expect effectively $0 either way — but run `terraform destroy`
when you're done so nothing is left running.
