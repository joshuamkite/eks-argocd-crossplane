terraform {
  backend "s3" {
    bucket = var.tfstate_bucket
    key    = var.tfstate_key
    region = var.tfstate_region
  }
}
