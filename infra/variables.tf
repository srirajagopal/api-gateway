# ─────────────────────────────────────────────────────────────────────────
# Input variables
# ─────────────────────────────────────────────────────────────────────────
# `variable` blocks declare the knobs this configuration exposes. They are
# NOT set here — Terraform reads their values from (in order of precedence)
# -var flags, a terraform.tfvars file, TF_VAR_* environment variables, or —
# if none of those are given — the `default` shown below. This project ships
# terraform.tfvars.example; copy it to terraform.tfvars to set real values
# without hardcoding them into the .tf files (and terraform.tfvars is
# .gitignore'd, since account/environment-specific values shouldn't be
# committed).

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  # Any region works here; us-east-1 is used as a default because it's the
  # oldest/most feature-complete region and has no surprises with newer
  # service availability.
  default = "us-east-1"
}

variable "stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  # API Gateway requires every deployment to be published under a named
  # "stage" (commonly dev/test/prod) before it's reachable over HTTPS. The
  # stage name becomes part of the invoke URL path, e.g.
  # https://<api-id>.execute-api.<region>.amazonaws.com/prod/hello.
  default = "prod"
}
