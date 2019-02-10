terraform {
  backend "s3" {
    region = "eu-west-2"

    bucket = "kayan-terra-state"
    key    = "component-network-test-peering.tfstate"
  }
}
