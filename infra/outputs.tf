# ─────────────────────────────────────────────────────────────────────────
# Outputs — values Terraform prints after `apply` and exposes to
# `terraform output`, for use by scripts, curl, Postman, etc.
# ─────────────────────────────────────────────────────────────────────────
# Without these, the invoke URL, function name, and API ID would have to be
# looked up manually in the AWS console after every apply.

output "invoke_url" {
  description = "Full HTTPS URL for GET /hello"
  # aws_api_gateway_stage exposes `invoke_url` as the base
  # (".../<stage>"), so the "/hello" path segment is appended here to give
  # back a URL that's directly curl-able / paste-able into Postman.
  value = "${aws_api_gateway_stage.hello_stage.invoke_url}/hello"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  # Handy for boto3 scripts (see scripts/smoke_test.py, scripts/build_lambda.py)
  # that need the function name to call boto3.client("lambda").invoke(...)
  # or update_function_code(...) directly, bypassing API Gateway.
  value = aws_lambda_function.hello.function_name
}

output "rest_api_id" {
  description = "ID of the REST API"
  # Useful for looking the API up in the AWS Console or via
  # `aws apigateway get-rest-api --rest-api-id <this value>` without having
  # to hunt for it by name.
  value = aws_api_gateway_rest_api.hello_api.id
}
