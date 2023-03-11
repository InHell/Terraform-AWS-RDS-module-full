#this is example of root main faile that's lay on top of folders and use module aws rds.

#start 1 2 ------------------------------------------------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.45.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
  }
}
provider "aws" {
  region = var.region
}



#sss
###### remote state loc #######------#--------№--------------------------------------------------------------------------------
terraform {
  backend "s3" {
    bucket = "s3_bucked_name_of_yours"
    key    = "folder_in_bucked/terraform.tfstate"
    region = "us-east-1"
  }
}


#-- main modules sector----------------------------------------------------------------------------------------------------------------


locals {
  multienv = var.environment
  # declarative bellow 
  # multienv = prod
}


module "rds_mssql_express" {
  source      = "./modules/rds_mssql_express"
  environment = local.multienv
}

