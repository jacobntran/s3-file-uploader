provider "aws" {
  region = "us-west-1"
}

### VARIABLES ###
variable "my_ip" {
  description = "Your public ip address"
  type        = string
}

variable "key_name" {
  description = "The key used to access your instances"
  type        = string
}

variable "bucket_name" {
  description = "Name of the bucket where you'll store your files"
  type        = string
}

output "bastion_host_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The public IP of the Bastion Host"
}

output "app_host_private_ip" {
  value       = aws_instance.app.private_ip
  description = "The private IP of the App Host"
}

### NETWORKING ###
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/27"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/28"
  availability_zone       = "us-west-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.0.16/28"
  availability_zone = "us-west-1b"

  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_eip" "nat_gw" {
  domain = "vpc"
}

resource "aws_nat_gateway" "public" {
  allocation_id = aws_eip.nat_gw.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "Public Subnet Route Table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public.id
  }

  tags = {
    Name = "Private Subnet Route Table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

### SERVICES ###
resource "aws_instance" "bastion" {
  ami                    = "ami-0d53d72369335a9d6"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "Bastion Host"
  }
}

resource "aws_instance" "app" {
  ami                    = "ami-0d53d72369335a9d6"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.s3_file_uploader.name

  tags = {
    Name = "S3 File Uploader Host"
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion_host"
  description = "Bastion Host Security Group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name        = "app_host"
  description = "Application Host Security Group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/28"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### STORAGE ###
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true ## change to false if you don't want terraform to destroy your objects when running terraform destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "s3" {
  description = "Key for encrypting S3 objects"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.id
      sse_algorithm     = "aws:kms"
    }
  }
}

### PERMISSIONS ###
resource "aws_iam_policy" "s3_file_uploader" {
  name        = "s3_file_uploader"
  description = "Used by S3 file uploader application to upload and download objects to your S3 bucket"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "${aws_s3_bucket.this.arn}",
          "${aws_s3_bucket.this.arn}/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "${aws_kms_key.s3.arn}"
      }
    ]
  })
}

resource "aws_iam_role" "s3_file_uploader" {
  name = "ec2_instance_s3_file_uploader_role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.s3_file_uploader.name
  policy_arn = aws_iam_policy.s3_file_uploader.arn
}

resource "aws_iam_instance_profile" "s3_file_uploader" {
  name = "ec2_instance_s3_file_uploader_instance_profile"
  role = aws_iam_role.s3_file_uploader.name
}