terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_profile" {
  description = "The AWS profile to use"
  type = string
  default = "default"
}

variable "aws_region" {
  description = "The AWS region"
  type = string
}

variable "vpc_cidr" {
  description = "VPC CiDR"
  type = string
}

variable "public_subnet_cidr" {
  description = "Public Subnet CiDR"
  type = string
}

variable "private_subnet_cidr" {
  description = "Private Subnet CiDR"
  type = string
}

variable "availability_zone" {
  description = "Availability zone"
  type = string
}

variable "public_instance_ami" {
  description = "Public AMI"
  type = string
}

variable "private_instance_ami" {
  description = "Private AMI"
  type = string
}

variable "instance_type" {
  description = "Instance type"
  type = string
}

variable "key_name" {
  description = "Name of the key file"
  type = string
}

variable "public_instance_private_ip" {
  description = "Public instance private ip"
  type = string
}

variable "private_instance_private_ip" {
  description = "Private instance private ip"
  type = string
}

# select the provider
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

# creating vpc
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "main vpc"
  }
}

# subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "public subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "private subnet"
  }
}

# aws ec2 instance
resource "aws_instance" "public_instance" {
  ami               = var.public_instance_ami
  instance_type     = var.instance_type
  availability_zone = var.availability_zone

  key_name = var.key_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.netif.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo Deployed via Terraform' > /var/www/html/index.html
              EOF

  tags = {
    Name = "public instance"
  }
}

resource "aws_instance" "private_instance" {
  ami               = var.private_instance_ami
  instance_type     = var.instance_type
  availability_zone = var.availability_zone

  key_name = var.key_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.private_netif.id
  }

  tags = {
    Name = "private instance"
  }
}

# internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main vpc gateway"
  }
}

# nat gateway
resource "aws_nat_gateway" "ngw" {
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.nat_eip.id

  tags = {
    Name = "gw NAT"
  }

  depends_on = [aws_internet_gateway.gw]
}

# route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public route table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "private route table"
  }
}

# route table association to subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# security groups
resource "aws_security_group" "secgrp" {
  name        = "public_sg"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "public security group"
  }
}

resource "aws_security_group_rule" "port_443" {
  for_each = toset(["0.0.0.0/0"])
  description       = "HTTPS traffic"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks = [each.value]
  security_group_id = aws_security_group.secgrp.id
}

resource "aws_security_group_rule" "port_80" {
  description       = "HTTP traffic"
  for_each = toset(["0.0.0.0/0"])
  from_port         = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.secgrp.id
  to_port           = 80
  type              = "ingress"
  cidr_blocks = [each.value]
}

resource "aws_security_group_rule" "port_22" {
  description       = "HTTP traffic"
  for_each = toset(["0.0.0.0/0"])
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.secgrp.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks = [each.value]
}

resource "aws_security_group_rule" "egress_sg" {
  description       = "All traffic"
  for_each = toset(["0.0.0.0/0"])
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.secgrp.id
  to_port           = 0
  type              = "egress"
  cidr_blocks = [each.value]
}

# network interface
resource "aws_network_interface" "netif" {
  subnet_id = aws_subnet.public.id
  private_ips = ["10.0.0.50"]
  security_groups = [aws_security_group.secgrp.id]
}

resource "aws_network_interface" "private_netif" {
  subnet_id = aws_subnet.private.id
  private_ips = ["10.0.1.50"]
  security_groups = [aws_security_group.secgrp.id]
}

# assigning elastic ip to instance
resource "aws_eip" "one" {
  instance = aws_instance.public_instance.id
  domain   = "vpc"

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

output "public_instance_public_ip" {
  value = aws_eip.one.public_ip
}
