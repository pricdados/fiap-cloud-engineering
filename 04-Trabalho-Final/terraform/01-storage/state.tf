provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "base-config-SEU_RM"
    key    = "trabalho-final/01-storage/terraform.tfstate"
    region = "us-east-1"
  }
}
