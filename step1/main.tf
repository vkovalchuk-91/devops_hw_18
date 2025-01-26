terraform {
  backend "s3"{
  bucket = "github-actions-slengpack"
  key = "terrraformRDS.tfstate"
  region = "eu-central-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "HW_18_VPC"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "HW_18_Internet-Gateway"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count = 3

  tags = {
    Name = "HW_18-NAT-EIP-${count.index + 1}"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  count         = 3
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "HW_18-NAT-Gateway-${count.index + 1}"
  }
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.0.0/20", 8, count.index)
  availability_zone = element(["eu-central-1a", "eu-central-1b", "eu-central-1c"], count.index)

  tags = {
    Name = "HW_18_Public-Subnet-${count.index + 1}"
  }
}


resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.16.0/20", 8, count.index)
  availability_zone = element(["eu-central-1a", "eu-central-1b", "eu-central-1c"], count.index)

  tags = {
    Name = "HW_18_Private-Subnet-${count.index + 1}"
  }
}


resource "aws_subnet" "database" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.32.0/20", 8, count.index)
  availability_zone = element(["eu-central-1a", "eu-central-1b", "eu-central-1c"], count.index)

  tags = {
    Name = "HW_18_Database-Subnet-${count.index + 1}"
  }
}


resource "aws_route_table" "public" {
  count  = 3
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "HW_18_Public-Route-Table-${count.index + 1}"
  }
}

resource "aws_route" "public" {
  count                  = 3
  route_table_id         = aws_route_table.public[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}


resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "HW_18_Private-Route-Table-${count.index + 1}"
  }
}

resource "aws_route" "private" {
  count                  = 3
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


resource "aws_route_table" "database" {
  count  = 3
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "HW_18_Database-Route-Table-${count.index + 1}"
  }
}

resource "aws_route_table_association" "database" {
  count          = 3
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}


resource "aws_security_group" "rds_sg" {
  name        = "slengpack-rds-sg"
  description = "Security Group for Slengpack RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SLENGPACK-RDS-SG"
  }
}


resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "slengpack-db-subnet-group"
  description = "Database Subnet Group for Slengpack RDS"
  subnet_ids = [
    aws_subnet.database[0].id,
    aws_subnet.database[1].id,
    aws_subnet.database[2].id
  ]

  tags = {
    Name = "SLENGPACK-DB-Subnet-Group"
  }
}


resource "aws_db_parameter_group" "custom_param_group" {
  name        = "slengpack-custom-param-group"
  family      = "mysql8.0"
  description = "Custom Parameter Group for Slengpack RDS"

  parameter {
    name  = "innodb_file_per_table"
    value = "1"
  }

  parameter {
    name  = "max_connections"
    value = "200"
  }

  tags = {
    Name = "SLENGPACK-Custom-Param-Group"
  }
}


resource "aws_db_instance" "slengpack_rds" {
  identifier                            = "slengpack-db-instance"
  allocated_storage                     = 20
  storage_type                          = "gp2"
  engine                                = "mysql"
  engine_version                        = "8.0"
  instance_class                        = "db.t4g.micro"
  db_name                               = "wordpress"
  username                              = "admin"
  password                              = "StrongPassword123!"
  db_subnet_group_name                  = aws_db_subnet_group.db_subnet_group.name
  parameter_group_name                  = aws_db_parameter_group.custom_param_group.name
  vpc_security_group_ids                = [aws_security_group.rds_sg.id]
  multi_az                              = false
  publicly_accessible                   = false
  skip_final_snapshot                   = true
  tags = {
    Name = "SLENGPACK-RDS"
  }
}

output "created_vpc_id" {
    value = aws_vpc.main.id
}

output "public_subnet_id_1" {
    value = aws_subnet.public[0].id
}

output "public_subnet_id_2" {
    value = aws_subnet.public[1].id
}

output "private_subnet_id_1" {
    value = aws_subnet.private[0].id
}

output "private_subnet_id_2" {
    value = aws_subnet.private[1].id
}

output "rds_endpoint" {
    value = aws_db_instance.slengpack_rds.endpoint
}
