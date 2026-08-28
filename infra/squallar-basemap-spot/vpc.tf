# A VPC of its own, not a share of `infra/aws-spot`'s.
#
# Two reasons, and the second is the one that matters. The obvious one is
# blast radius: this stack launches a machine that holds write credentials for
# the basemap bucket, and it should not share a network with unrelated CI. The
# real one is LIFECYCLE -- `infra/aws-spot` is someone else's stack with its own
# reasons to change, and a `terraform destroy` there must not be able to strand
# a build that is 40 minutes into a planet run.
#
# The CIDR deliberately differs from `aws-spot`'s 10.100.0.0/16. Nothing peers
# them, so an overlap would be legal -- it is chosen to be distinct so that a
# flow log or a security-group rule read in isolation is unambiguous about which
# stack it belongs to.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "build" {
  cidr_block           = "10.101.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "squallar-basemap-build" }
}

resource "aws_internet_gateway" "build" {
  vpc_id = aws_vpc.build.id
  tags   = { Name = "squallar-basemap-build" }
}

# A PUBLIC subnet with a public IP, and NO NAT GATEWAY ANYWHERE IN THIS STACK.
#
# DO NOT ADD ONE. It reads as the tidier choice and it silently taxes every byte
# this stack pulls, at $0.045/GB of processing on top of ~$32/month standing:
#
#   planet PBF, per build        94.5 GB  ->  ~$4.25   (vs ~$2.75 of compute)
#   Copernicus GLO-30, one-shot   1.5 TB  ->  ~$67.50  (vs ~$3 of compute)
#
# The contour job alone would cost twenty times its own compute in transfer
# processing. Inbound to AWS is $0 and both sources are AWS Open Data buckets
# (`osm-planet-us-west-2`, `copernicus-dem-30m` -- verified anonymously
# readable, so not requester-pays), which means the download is genuinely free
# ONLY on a path with no NAT in it.
#
# A public IP on a public subnet costs nothing, and the security group below
# allows no inbound at all -- not even SSH -- so a public address exposes
# nothing to reach.
resource "aws_default_route_table" "build" {
  default_route_table_id = aws_vpc.build.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.build.id
  }

  tags = { Name = "squallar-basemap-build-public" }
}

# THREE AZs, AND THIS IS THE SINGLE BIGGEST LEVER ON SPOT AVAILABILITY.
#
# Spot capacity is per (instance type, availability zone). One subnet in one AZ
# with one instance type is ONE POOL -- and when that pool is empty, retrying is
# pointless because there is nowhere else to look. Three AZs against the six
# instance types in `var.fleet_instance_types` gives EIGHTEEN pools, and the
# fleet takes whichever has capacity.
#
# This is why the trigger is `createFleet` and not `runInstances`: RunInstances
# takes exactly one subnet and one instance type, so it structurally cannot
# express any of this.
locals {
  build_azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_subnet" "build_public" {
  for_each = toset(local.build_azs)

  vpc_id                  = aws_vpc.build.id
  cidr_block              = cidrsubnet(aws_vpc.build.cidr_block, 8, index(local.build_azs, each.key) + 1)
  map_public_ip_on_launch = true
  availability_zone       = each.key
  tags                    = { Name = "squallar-basemap-build-${each.key}" }
}

resource "aws_route_table_association" "build_public" {
  for_each = aws_subnet.build_public

  subnet_id      = each.value.id
  route_table_id = aws_default_route_table.build.id
}

# EGRESS ONLY, AND NO INGRESS RULE AT ALL -- not even SSH.
#
# The instance is not interactive: it runs one script from user-data and
# terminates itself. An SSH rule would exist only to make debugging convenient,
# and the cost of that convenience is a publicly-addressed machine holding R2
# write credentials with a listening service on it. Logs go to CloudWatch
# instead, which is readable without a network path back in.
resource "aws_security_group" "build" {
  name        = "squallar-basemap-build"
  description = "Planet build box: egress only, no inbound, no SSH"
  vpc_id      = aws_vpc.build.id

  egress {
    description = "Planet PBF download, R2 upload, SMTP relay, SSM, CloudWatch"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "squallar-basemap-build" }
}
