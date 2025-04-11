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
