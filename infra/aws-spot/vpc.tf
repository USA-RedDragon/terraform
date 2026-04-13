data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "ci" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "ci-spot-vpc" }
}

resource "aws_internet_gateway" "ci" {
  vpc_id = aws_vpc.ci.id
}

resource "aws_subnet" "ci_public" {
  vpc_id                  = aws_vpc.ci.id
  cidr_block              = "10.100.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = { Name = "ci-spot-public" }
}

resource "aws_route_table" "ci_public" {
  vpc_id = aws_vpc.ci.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ci.id
  }
}

resource "aws_route_table_association" "ci_public" {
  subnet_id      = aws_subnet.ci_public.id
  route_table_id = aws_route_table.ci_public.id
}
