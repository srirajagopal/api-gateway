# ─────────────────────────────────────────────────────────────────────────
# API Gateway REST API: /hello resource, GET method, Lambda integration
# ─────────────────────────────────────────────────────────────────────────
# API Gateway's REST API model is deliberately granular — a URL path is
# built up resource-by-resource, and each HTTP verb on a resource is its own
# "method" with its own "integration" describing what happens when it's
# called. This file walks through that chain from the top (the API
# container) down to the deployed, callable endpoint.

# The API "container" — doesn't define any paths or behavior on its own.
resource "aws_api_gateway_rest_api" "hello_api" {
  name        = "hello-api"
  description = "Simple REST API exposing GET /hello"
}

# A "resource" in API Gateway = one URL path segment. This adds the "hello"
# segment as a child of the API's automatically-created root ("/"), so the
# full path becomes "/hello". A more nested API (e.g. "/users/{id}") would
# chain more aws_api_gateway_resource blocks, each pointing at the previous
# one's id as its parent_id.
resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.hello_api.id
  parent_id   = aws_api_gateway_rest_api.hello_api.root_resource_id
  path_part   = "hello"
}

# A "method" = one HTTP verb allowed on a resource. A resource with no
# method defined for a given verb returns 403 for requests using it — e.g.
# POST /hello would fail because only GET is declared here.
resource "aws_api_gateway_method" "get_hello" {
  rest_api_id = aws_api_gateway_rest_api.hello_api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = "GET"
  # "NONE" = no IAM/Cognito/API-key auth required to call this method. This
  # is what makes the endpoint publicly reachable from Postman or a browser
  # with no credentials.
  authorization = "NONE"
}

# The "integration" wires a method to whatever actually handles the
# request — here, the Lambda function. type = "AWS_PROXY" is the important
# choice: it means API Gateway does NOT try to map/transform the request —
# it forwards the entire HTTP request (method, headers, query string, body,
# path params) as one JSON "event" object straight to Lambda, and expects
# the Lambda response back in a specific
# {statusCode, headers, body} shape (see lambda/hello/handler.py). The
# alternative, "AWS" (non-proxy), would require hand-written request/response
# mapping templates in Terraform — proxy integration is the standard choice
# for "Lambda is basically the whole backend" APIs like this one.
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.hello_api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = aws_api_gateway_method.get_hello.http_method
  # Lambda's own invocation API is always invoked via POST internally,
  # regardless of what HTTP verb the *client* used (GET, in our case). This
  # is an API Gateway/Lambda-proxy quirk, not a mistake — AWS_PROXY
  # integrations always set this to "POST".
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello.invoke_arn
}

# By default, nothing is allowed to invoke a Lambda function — not even API
# Gateway, despite the integration above pointing at it. This resource is a
# *resource-based* policy on the Lambda function itself, separate from the
# integration, that explicitly grants the API Gateway service permission to
# call it. Forgetting this is the single most common cause of a
# "403 Forbidden" response with an otherwise-correct integration.
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  # Scopes the grant down to only this specific API + method + path, rather
  # than "any API Gateway API in this account can invoke this function".
  # execution_arn already identifies the REST API; the "/*/GET/hello" suffix
  # narrows it to (any stage)/(GET)/(the hello resource).
  source_arn = "${aws_api_gateway_rest_api.hello_api.execution_arn}/*/${aws_api_gateway_method.get_hello.http_method}/hello"
}

# Defining resources/methods/integrations above does NOT make the API
# callable — API Gateway requires an explicit "deployment" (a snapshot of
# the current configuration) before any of it is live.
resource "aws_api_gateway_deployment" "hello_deployment" {
  rest_api_id = aws_api_gateway_rest_api.hello_api.id

  # aws_api_gateway_deployment has no attributes of its own that change when
  # the resource/method/integration change, so Terraform wouldn't normally
  # know a *new* deployment is needed after, say, editing the integration.
  # This `triggers` block manually computes a hash of the pieces that make
  # up the API's behavior; whenever that hash changes, Terraform creates a
  # brand new deployment (redeploying is the API Gateway equivalent of
  # "restart the server to pick up the config change").
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.get_hello.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  # Deployments can't simply be updated in place — a stage always points at
  # a specific deployment ID. create_before_destroy tells Terraform to stand
  # up the *new* deployment first, re-point the stage at it (see the stage
  # resource below), and only then destroy the old deployment — avoiding a
  # brief window where the API has no valid deployment at all.
  lifecycle {
    create_before_destroy = true
  }

  # Explicit dependency: without this, Terraform could create the deployment
  # before the integration exists (since nothing in this resource's
  # arguments directly references the integration by attribute), producing
  # a deployment that doesn't actually route to Lambda yet.
  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# A deployment on its own has no URL — it must be published under a named
# "stage" (e.g. dev/test/prod) to become reachable. The stage is what
# actually appears in the invoke URL:
# https://<api-id>.execute-api.<region>.amazonaws.com/<stage_name>/hello
resource "aws_api_gateway_stage" "hello_stage" {
  deployment_id = aws_api_gateway_deployment.hello_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.hello_api.id
  stage_name    = var.stage_name
}
