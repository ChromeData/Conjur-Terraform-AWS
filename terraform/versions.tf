terraform {
  required_version = ">= 1.9.0"

  required_providers {
    conjur = {
      source  = "cyberark/conjur"
      version = "~> 0.6"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Authenticates as the host identity created by conjur/policy/terraform-runner.yml.
# Credentials for Conjur ITSELF come from the environment, this is the one
# bootstrap secret you cannot eliminate, only reduce. Chain of trust has to start
# somewhere; the honest version of this pattern names that rather than pretending
# it is turtles all the way down.
#
#   CONJUR_APPLIANCE_URL=http://localhost:8080
#   CONJUR_ACCOUNT=lab
#   CONJUR_AUTHN_LOGIN=host/terraform-runner/pipeline
#   CONJUR_AUTHN_API_KEY=<emitted once at policy load>
provider "conjur" {}
