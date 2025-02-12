terraform {
  backend "s3" {
    bucket = var.tf_state["bucket"]
    key    = var.tf_state["key"]
    region = var.tf_state["region"]
  }
}
