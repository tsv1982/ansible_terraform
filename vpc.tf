resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    "Name" = "petclinic_vpc"
  }
}

data "aws_availability_zones" "available" {}

# private
resource "aws_subnet" "private_subnet" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "petclinic_subnet_instance"
  }
}

# public
resource "aws_subnet" "public-subnet" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "petclinic subnet public"
  }
}

resource "aws_internet_gateway" "nat_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "petclinic_internet_gateway"
  }
}

resource "aws_route_table" "nat_gateway" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "nat_gateway" {
  subnet_id = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.nat_gateway.id
}

resource "aws_eip" "nat_gateway" {
  vpc = true
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion_instance.id
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id = aws_subnet.public-subnet.id
  tags = {
    "Name" = "petclinic nat gateway"
  }
}

resource "aws_route_table" "instance" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "instance" {
  subnet_id = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.instance.id
}



