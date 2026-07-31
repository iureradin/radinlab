# ---
# Immich - Backend Configuration
# Remote state stored in S3
# ---

terraform {
  backend "s3" {
    bucket = "radinlab-terraform-state"
    key    = "prod/immich/terraform.tfstate"
    region = "us-east-1"
  }
}
