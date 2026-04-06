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

# Build the TypeScript function - force rebuild in CI/CD with environment variable
resource "null_resource" "build_lambda" {
  triggers = {
    source_hash = filemd5("${var.source_dir}/index.ts")
    # Force rebuild in CI/CD pipelines and GitHub Actions
    ci_context = try(var.ci_build_id, "local")
  }

  provisioner "local-exec" {
    command     = "mkdir -p ${var.source_dir}/dist && cd ${var.source_dir} && npm install && npm run build && npm install --omit=dev"
    interpreter = ["bash", "-c"]
  }
}

# Ensure dist directory exists before archiving
resource "null_resource" "ensure_dist" {
  triggers = {
    build_id = null_resource.build_lambda.id
  }

  provisioner "local-exec" {
    command = "mkdir -p ${var.source_dir}/dist"
  }
}

# Archive the Lambda function code using RESOURCE (not data source) for CI/CD
resource "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${var.source_dir}/dist"
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [null_resource.ensure_dist]
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
  filename         = archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = var.handler
  runtime          = var.runtime
  source_code_hash = archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = "production"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    archive_file.lambda_zip
  ]
}
