# ─────────────────────────────────────────────────────────────────────────
# Terraform + provider configuration
# ─────────────────────────────────────────────────────────────────────────
# This block does two things: (1) pins the minimum Terraform CLI version
# required for the syntax used here, and (2) declares which *providers*
# (plugins that know how to talk to a specific API) this configuration
# needs, and which version range of each is acceptable.
terraform {
  required_version = ">= 1.5"

  required_providers {
    # The AWS provider is what turns resource blocks like
    # `aws_lambda_function` into actual AWS API calls (CreateFunction,
    # UpdateFunctionCode, etc.). "~> 5.0" means "any 5.x version, but not 6.0" —
    # this avoids an unannounced breaking change silently changing behavior.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # The archive provider has no AWS API of its own — it's a local utility
    # provider used purely to zip files on disk (see the `archive_file` data
    # source in lambda.tf). Lambda requires code to be uploaded as a zip, so
    # this replaces what would otherwise be a manual `zip` shell command.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configures the *instance* of the aws provider declared above: which AWS
# region API calls should target. Every resource in this project (Lambda,
# API Gateway, IAM) is regional except IAM itself, which is global but still
# needs a region to know which regional endpoint to call.
#
# var.aws_region is defined in variables.tf and set in terraform.tfvars —
# keeping it as a variable (rather than hardcoding "us-east-1" here) means
# changing region is a one-line edit, not a find-and-replace across files.
provider "aws" {
  region = var.aws_region

  # default_tags applies these tags to every resource in this configuration
  # that supports tagging, without adding a `tags` argument to each resource
  # block individually. IAM role attachments, API Gateway resources/methods/
  # integrations/deployments, and Lambda permissions have no tags concept in
  # the AWS API and are unaffected either way.
  default_tags {
    tags = {
      class    = "cs218"
      exercise = "api-gateway"
    }
  }
}
