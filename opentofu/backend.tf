terraform {
  # Using local backend for demonstration
  # In production, use remote S3 backend with proper access controls
  backend "local" {
    path = "terraform.tfstate"
  }
}
