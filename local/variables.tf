variable "aws_region" {
  description = "Region reported to the emulator (any single region)."
  type        = string
  default     = "us-east-1"
}

variable "emulator_endpoint" {
  description = "Base URL of the running AWS Emulator."
  type        = string
  default     = "https://127.0.0.1:9297"
}

variable "function_name" {
  description = "Lambda function name."
  type        = string
  default     = "my-func"
}

variable "table_name" {
  description = "DynamoDB table name the Lambda reads/writes."
  type        = string
  default     = "lambda-test-table"
}

variable "source_dir" {
  description = "Directory containing the TypeScript Lambda source."
  type        = string
  default     = "../../../src-local"
}
