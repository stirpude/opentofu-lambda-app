variable "aws_region" {
  description = "AWS region for the Lambda function"
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "hello-world-typescript"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs20.x"
}

variable "handler" {
  description = "Lambda handler"
  type        = string
  default     = "index.handler"
}

variable "source_dir" {
  description = "Source directory for Lambda function"
  type        = string
  default     = "../src"
}

variable "ci_build_id" {
  description = "Build ID for forcing rebuilds in CI/CD pipelines"
  type        = string
  default     = ""
}
