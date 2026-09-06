resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = var.public
}

resource "aws_internet_gateway" "this" { # internet gateway is a resource that allows communication between the VPC and the internet
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "this" {
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = var.cidr_block
  gateway_id             = aws_internet_gateway.this.id # why do we need to specify the gateway id here?
}

resource "aws_route_table_association" "this" { # associates the public route table with the public subnet
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}
