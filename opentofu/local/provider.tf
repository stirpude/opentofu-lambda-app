provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Point the services to your fake cloud
  endpoints {
    lambda   = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
  }
}
