terraform {
  backend "s3" {
    bucket         = "devops-assignment-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devops-assignment-tfstate-lock"
    encrypt        = true
  }
}
