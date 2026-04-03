terraform {
  backend "s3" {
    bucket         = "opentofu-state-391122274211"
    key            = "opentofu.tfstate"
    region         = "us-east-1"
    dynamodb_table = "opentofu-locks"
    encrypt        = true
  }
}
