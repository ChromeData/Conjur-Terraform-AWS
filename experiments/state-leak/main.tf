# The minimum configuration that answers the lab's central question.
#
# No AWS provider, no AWS resources, no cost, no credentials that can do
# anything. Just: read a secret from Conjur with the data source, apply, and
# look at what Terraform wrote to disk.
#
# Isolating it this way matters. In the full lab the data source sits next to a
# VPC and an EC2 instance, and someone can always argue the credential appeared
# in state because of the provider block or a resource attribute. Here there is
# nothing else in the configuration. Whatever ends up in state came from the
# data source.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    conjur = {
      source  = "cyberark/conjur"
      version = "~> 0.6"
    }
  }
}

provider "conjur" {}

data "conjur_secret" "access_key_id" {
  name = "aws-credentials/access-key-id"
}

data "conjur_secret" "secret_access_key" {
  name = "aws-credentials/secret-access-key"
}

data "conjur_secret" "region" {
  name = "aws-credentials/region"
}

# Something trivial so there is a resource to apply. It deliberately does NOT
# reference the secrets, so nothing here can be blamed for putting them in state.
resource "terraform_data" "marker" {
  input = "state-leak experiment"
}
