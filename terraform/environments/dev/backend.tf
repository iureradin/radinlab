terraform {
  backend "s3" {
    bucket = "radinlab-terraform-state"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }
}
