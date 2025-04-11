variable "credential_source" {
  description = <<-EOT
    How the AWS provider gets its credentials.

      summon      Conjur -> environment -> provider (via `summon`). Terraform
                  never holds a value it could write to state. This is the
                  correct pattern and the default.

      datasource  Conjur -> conjur_secret data source -> provider. The
                  intuitive approach, kept so the leak can be demonstrated
                  rather than described. See `make prove-leak`.
  EOT
  type        = string
  default     = "summon"

  validation {
    condition     = contains(["summon", "datasource"], var.credential_source)
    error_message = "credential_source must be 'summon' or 'datasource'."
  }
}

variable "region" {
  description = "AWS region. Used on the summon path; the datasource path reads it from Conjur."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  default     = "pamlab01"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "operator_cidr" {
  description = <<-EOT
    Your public IP in CIDR form, e.g. "203.0.113.4/32".
    Deliberately has no default — a default here would eventually become 0.0.0.0/0
    in someone's copy of this repo, and that is exactly the class of mistake this
    lab is about.
  EOT
  type        = string

  validation {
    condition     = var.operator_cidr != "0.0.0.0/0"
    error_message = "Refusing to open SSH to the world. Set operator_cidr to your own /32."
  }
}
