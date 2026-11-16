# Build the TypeScript Lambda (compile + prod deps) before archiving.
data "external" "build_lambda" {
  program = ["bash", "-c", "cd ${path.module}/${var.source_dir} && npm install >/dev/null 2>&1 && npm run build >/dev/null 2>&1 && echo '{\"status\": \"built\"}'"]
}

# Package only the compiled output. The nodejs20.x runtime in the emulator
# (like AWS) ships the AWS SDK v3, so node_modules does not need bundling.
resource "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/${var.source_dir}/dist"
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [data.external.build_lambda]
}

# DynamoDB table the Lambda reads from / writes to.
resource "aws_dynamodb_table" "test_table" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "Emulator Lambda Test Table"
    Environment = "local-emulator"
  }
}

# Execution role the Lambda assumes.
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# The emulator enforces IAM, so the role needs explicit DynamoDB permissions,
# exactly as it would on AWS.
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.function_name}-dynamodb"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:DescribeTable"
      ]
      Resource = [
        aws_dynamodb_table.test_table.arn,
        "${aws_dynamodb_table.test_table.arn}/*"
      ]
    }]
  })
}

# Lambda function. TABLE_NAME is passed in; AWS_ENDPOINT_URL is intentionally
# NOT set so the handler uses default SDK config and the emulator routes the
# calls (and injects the role's credentials) automatically.
resource "aws_lambda_function" "test" {
  function_name = var.function_name
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  role          = aws_iam_role.lambda_role.arn

  filename         = archive_file.lambda_zip.output_path
  source_code_hash = archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_dynamodb,
    aws_dynamodb_table.test_table
  ]
}

output "function_name" {
  value = aws_lambda_function.test.function_name
}

output "function_arn" {
  value = aws_lambda_function.test.arn
}

output "table_name" {
  value = aws_dynamodb_table.test_table.name
}

output "emulator_endpoint" {
  value = var.emulator_endpoint
}
