terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

# AWS provider pointed at a locally running AWS Emulator
# (https://github.com/aws/aws-emulator). The emulator serves HTTPS on
# 127.0.0.1:9297 with a self-signed certificate and, when started with
# "-a off", accepts any SigV4-signed request. We therefore use dummy static
# credentials, skip the credential/account lookups, and skip TLS verification.
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  insecure                    = true
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    lambda   = var.emulator_endpoint
    dynamodb = var.emulator_endpoint
    iam      = var.emulator_endpoint
    sts      = var.emulator_endpoint
    logs     = var.emulator_endpoint
  }
}
