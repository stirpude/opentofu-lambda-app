# Build the TypeScript function for src-local
data "external" "build_lambda_local" {
  program = ["bash", "-c", "cd ${path.module}/../../src-local && npm install >/dev/null 2>&1 && npm run build >/dev/null 2>&1 && npm install --omit=dev >/dev/null 2>&1 && echo '{\"status\": \"built\"}'"]
}

# Archive the Lambda function code from src-local
resource "archive_file" "lambda_zip_local" {
  type        = "zip"
  source_dir  = "${path.module}/../../src-local/dist"
  output_path = "${path.module}/../../src-local/dist/function.zip"

  depends_on = [data.external.build_lambda_local]
}

# IAM Role for Lambda
locals {
  lambda_role_arn = "arn:aws:iam::000000000000:role/floci-lambda-role"
}

# Lambda Function
resource "aws_lambda_function" "test" {
  function_name = "my-func"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  role          = local.lambda_role_arn

  filename         = archive_file.lambda_zip_local.output_path
  source_code_hash = archive_file.lambda_zip_local.output_base64sha256
}

# DynamoDB Test Table for Floci local testing
resource "aws_dynamodb_table" "test_table" {
  name         = "lambda-test-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "Floci Lambda Test Table"
    Environment = "local"
  }
}
