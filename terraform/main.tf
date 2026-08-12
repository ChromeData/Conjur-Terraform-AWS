# ---------------------------------------------------------------------------
# Secret retrieval
#
# These are data sources, not resources. That distinction is the entire point:
# a data source is read at plan time and its value is not persisted as managed
# state. Terraform still records data source results in state, which is why the
# values below are consumed directly by the provider block and never surfaced as
# a resource attribute or output.
#
# Verify with `make verify` rather than trusting this comment.
# ---------------------------------------------------------------------------

data "conjur_secret" "aws_access_key_id" {
  name = "aws-credentials/access-key-id"
}

data "conjur_secret" "aws_secret_access_key" {
  name = "aws-credentials/secret-access-key"
}

data "conjur_secret" "aws_region" {
  name = "aws-credentials/region"
}

provider "aws" {
  region     = data.conjur_secret.aws_region.value
  access_key = data.conjur_secret.aws_access_key_id.value
  secret_key = data.conjur_secret.aws_secret_access_key.value

  default_tags {
    tags = {
      Purpose   = "pam-cloud-lab"
      Lab       = "01-conjur-terraform-aws"
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Minimal but non-trivial infrastructure.
#
# A VPC with a bastion is chosen deliberately over "an S3 bucket": it forces the
# apply to run long enough to expose the access-token TTL question, which is the
# interesting failure mode of this pattern.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion"
  description = "Lab bastion. SSH from operator CIDR only."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-bastion" }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${var.name_prefix}-bastion" }
}
