terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# GitHub Actions deployment trigger

provider "aws" {
  region = var.aws_region
}

# Build the TypeScript function FIRST
resource "null_resource" "build_lambda" {
  triggers = {
    source_hash = filemd5("${var.source_dir}/index.ts")
  }

  provisioner "local-exec" {
    command     = "cd ${var.source_dir} && npm install && npm run build && npm install --omit=dev"
    interpreter = ["bash", "-c"]
  }
}

# Archive the Lambda function code (no ensure_dist needed - build creates it)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${var.source_dir}/dist"
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [null_resource.build_lambda]
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Lambda function
resource "aws_lambda_function" "hello_world" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = var.handler
  runtime          = var.runtime
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = "production"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    data.archive_file.lambda_zip
  ]
}
