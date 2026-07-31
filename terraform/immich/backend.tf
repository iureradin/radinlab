# ---
# Immich - Backend Configuration
# Using local backend (switch to remote as needed)
# ---

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
