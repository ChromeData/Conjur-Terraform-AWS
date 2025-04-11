# How the AWS provider gets its credentials — the whole point of this lab.
#
# Two paths, switchable, because the comparison IS the finding:
#
#   summon      (default)  Conjur -> environment -> provider. Terraform never
#                          sees a value it could record.
#
#   datasource             Conjur -> conjur_secret data source -> provider.
#                          The intuitive approach. Leaks into state.
#
# Run `make prove-leak` to see the difference measured rather than argued.

# Data sources are created only on the leaky path. count = 0 on the default
# path means they are never read, so nothing lands in state.
data "conjur_secret" "aws_access_key_id" {
  count = var.credential_source == "datasource" ? 1 : 0
  name  = "aws-credentials/access-key-id"
}

data "conjur_secret" "aws_secret_access_key" {
  count = var.credential_source == "datasource" ? 1 : 0
  name  = "aws-credentials/secret-access-key"
}

data "conjur_secret" "aws_region" {
  count = var.credential_source == "datasource" ? 1 : 0
  name  = "aws-credentials/region"
}

locals {
  # On the summon path these are null, and a null provider argument means
  # "fall back to the normal AWS credential chain" - which is the environment
  # Summon populated.
  aws_access_key = var.credential_source == "datasource" ? data.conjur_secret.aws_access_key_id[0].value : null
  aws_secret_key = var.credential_source == "datasource" ? data.conjur_secret.aws_secret_access_key[0].value : null
  aws_region     = var.credential_source == "datasource" ? data.conjur_secret.aws_region[0].value : var.region
}

provider "aws" {
  region     = local.aws_region
  access_key = local.aws_access_key
  secret_key = local.aws_secret_key

  default_tags {
    tags = {
      Purpose   = "pam-cloud-lab"
      Lab       = "01-conjur-terraform-aws"
      ManagedBy = "terraform"
    }
  }
}
