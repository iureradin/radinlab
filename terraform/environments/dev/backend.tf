terraform {
  backend "s3" {
    bucket = "radinlab-terraform-state"
    key    = "dev/terraform.tfstate"
    region = "sa-east-1"
  }
}
