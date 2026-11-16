# Floci local AWS deployment
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    lambda = "http://localhost:4566"
    iam    = "http://localhost:4566"
  }
}

# Build and package Lambda
data "external" "build_lambda" {
  program = ["bash", "-c", "cd ${path.module}/../src && npm install >/dev/null 2>&1 && npm run build >/dev/null 2>&1 && npm install --omit=dev >/dev/null 2>&1 && echo '{\"status\": \"built\"}'"]
}

resource "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dist"
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [data.external.build_lambda]
}

# IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "floci-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "hello_world" {
  filename         = archive_file.lambda_zip.output_path
  function_name    = "hello-world"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = "floci-local"
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

output "function_name" {
  value = aws_lambda_function.hello_world.function_name
}

output "function_arn" {
  value = aws_lambda_function.hello_world.arn
}
