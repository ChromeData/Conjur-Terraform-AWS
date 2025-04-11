# Note what is NOT here: no credential values, not even marked sensitive.
# `sensitive = true` hides a value from CLI output — it does not remove it from
# state. The only way to keep a secret out of state is to never make it an output
# or a resource attribute in the first place.

output "vpc_id" {
  description = "Lab VPC ID."
  value       = aws_vpc.lab.id
}

output "bastion_public_ip" {
  description = "Public IP of the lab bastion."
  value       = aws_instance.bastion.public_ip
}

output "conjur_secrets_consumed" {
  description = "Which Conjur variables this configuration reads. Names only, no values."
  value = [
    "aws-credentials/access-key-id",
    "aws-credentials/secret-access-key",
    "aws-credentials/region",
  ]
}
