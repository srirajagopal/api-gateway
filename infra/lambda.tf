# ─────────────────────────────────────────────────────────────────────────
# Lambda function and the IAM role it runs as
# ─────────────────────────────────────────────────────────────────────────

# `archive_file` is a *data source*, not a resource — it doesn't create
# anything in AWS. It runs locally, on every `terraform plan`, to zip the
# Lambda source into a deployment package. Lambda's API only accepts code as
# a zip (or a container image); this removes the need for a separate manual
# `zip` step before every deploy.
data "archive_file" "hello_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/hello/handler.py"
  # path.module = this file's own directory (infra/), so the zip always
  # lands at infra/hello.zip regardless of where `terraform` is invoked from.
  output_path = "${path.module}/hello.zip"
}

# Every Lambda function must run as an IAM role — this is that role. On its
# own an IAM role does nothing; it becomes useful once (a) something is
# allowed to assume it (the trust policy below) and (b) permissions are
# attached to it (the policy attachment below).
resource "aws_iam_role" "lambda_exec" {
  name = "hello-lambda-exec-role"

  # The "trust policy": who/what is allowed to assume this role. Here it's
  # scoped to the Lambda *service itself* (lambda.amazonaws.com) — meaning
  # only the Lambda runtime can act as this role, not IAM users or other
  # AWS services. jsonencode(...) lets us write the policy as an HCL map
  # instead of a raw JSON string, while still producing the JSON IAM expects.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# The trust policy above only says *who* can assume the role — this attaches
# the actual *permissions* the role grants once assumed. AWSLambdaBasicExecutionRole
# is an AWS-managed policy that grants exactly the CloudWatch Logs actions
# (CreateLogGroup/CreateLogStream/PutLogEvents) a Lambda function needs to
# write its own logs. Without this, the function would still run, but any
# print()/logging output — and any error tracebacks — would be silently
# dropped instead of showing up in CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The Lambda function itself.
resource "aws_lambda_function" "hello" {
  function_name = "hello-function"
  # Attaches the role+permissions defined above — this is what the function
  # "runs as" when AWS invokes it.
  role = aws_iam_role.lambda_exec.arn
  # "handler.handler" = <filename without .py>.<function name>. Our source
  # file is handler.py and the entry-point function inside it is `handler`,
  # matching lambda/hello/handler.py.
  handler = "handler.handler"
  runtime = "python3.12"

  # Where the code comes from and how Terraform knows it changed:
  filename = data.archive_file.hello_lambda.output_path
  # AWS Lambda only redeploys code when this hash changes. Without wiring
  # source_code_hash to the zip's own hash, editing handler.py would NOT
  # trigger a redeploy on `terraform apply` — Terraform would see the same
  # `filename` value and assume nothing changed.
  source_code_hash = data.archive_file.hello_lambda.output_base64sha256

  # Max execution time before AWS kills the invocation. The function does
  # no I/O, so the default (3s) would work too; set explicitly instead of
  # relying on the provider default.
  timeout = 5
}
