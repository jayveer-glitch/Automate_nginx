terraform {
  required_version = "~> 1.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  # You can change this region
  region = "ap-south-1"
}

# --- 1. Find the Amazon Linux AMI ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --- 2. Create a VPC (Network) ---
# This was missing and would have caused a "No default VPC" error.
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "My-VPC"
  }
}

# --- 3. Create a Public Subnet ---
# The instance needs a subnet to live in.
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"

  tags = {
    Name = "My-Subnet"
  }
}

# --- 4. Create the Security Group (Firewall) ---
# This is the corrected version of your "ssh" block.
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id # Must be associated with your VPC

  # Allow SSH (Port 22)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: Open to the world.
  }

  # Allow HTTP (Port 80)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "My-Nginx-SG"
  }
}

# --- 5. Create the EC2 Instance (Web Server) ---
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  # Attach the subnet and security group
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  # User_data script for Amazon Linux 2
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "My-nginx-server"
  }
}

# --- 6. Output the Server's Public IP ---
output "server_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web_server.public_ip
}
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "My-VPC-IGW"
  }
}
resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

  # This is the rule that sends internet traffic to the gateway
  route {
    cidr_block = "0.0.0.0/0" # "Anywhere on the internet"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "My-Public-Route-Table"
  }
}
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public_route.id
}
