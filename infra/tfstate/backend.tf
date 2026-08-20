terraform {
  backend "s3" {
    # bucketはdeploy.shから-backend-configで指定する
    key    = "sakuraevl/tfstate/terraform.tfstate"
    region = "jp-east-1"

    endpoints = {
      s3 = "https://s3.tky01.sakurastorage.jp"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
