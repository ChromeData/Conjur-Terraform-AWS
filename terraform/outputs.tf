output "credential_source" {
  description = "Which credential path this state was built with. Read by the verify script."
  value       = var.credential_source
}

output "bastion_public_ip" {
  description = "Public IP of the lab bastion."
  value       = aws_instance.bastion.public_ip
}

output "vpc_id" {
  description = "Lab VPC."
  value       = aws_vpc.lab.id
}

# Deliberately absent: any output carrying a credential.
#
# An output is the one place a secret is guaranteed to land in state AND be
# printed to the terminal AND be readable by any downstream configuration that
# consumes this state as a remote data source. If you find yourself wanting one,
# that is the signal to reach for Summon instead.
