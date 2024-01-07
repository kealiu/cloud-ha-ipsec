# Copyright 2024 ke.liu#foxmail.com

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_subnet" "ipsec_subnet" {
  id = var.ipsec_subnet_id
}

# create the default sg
resource "aws_security_group" "ipsec_sg" {
  name        = "Allow IPSec VPN"
  description = "Allow TLS inbound traffic"
  vpc_id      = data.aws_subnet.ipsec_subnet.vpc_id

  ingress {
    description      = "SSH from Local"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "IPSec UDP 500"
    from_port        = 500
    to_port          = 500
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "IPSec UDP 4500"
    from_port        = 4500
    to_port          = 4500
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ha-ipsec_sg"
  }
}

# create Role
resource "aws_iam_role" "ha-ipsec-role" {
  name = "ha-ipsec-role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = var.ipsec_china_region ? "ec2.amazonaws.com.cn" : "ec2.amazonaws.com"
        }
      },
    ]
  })
  
  tags = {
    Name = "ha-ipsec-role"
  }
}

resource "aws_iam_role_policy" "ha-ipsec-role" {
    name        = "ha-ipsec-role"
    role        = aws_iam_role.ha-ipsec-role.id

    # Terraform's "jsonencode" function converts a
    # Terraform expression result to valid JSON syntax.
  
    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
            "Sid": "Stmt1704598082947",
            "Action": [
                "ssm:DeleteParameter",
                "ssm:DescribeParameters",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
                "ssm:PutParameter",
                "ec2:DescribeRouteTables",
                "ec2:ReplaceRoute",
                "sns:Publish"
            ],
            "Effect": "Allow",
            "Resource": "*"
            }
        ]
    })
}


resource "aws_iam_instance_profile" "ha-ipsec-role" {
  name = "ha-ipsec-role"
  role = aws_iam_role.ha-ipsec-role.name
}

# create instances
resource "aws_instance" "HA-IPSec-A" {
    depends_on = [aws_iam_instance_profile.ha-ipsec-role]
    ami             = data.aws_ami.ubuntu.id
    subnet_id       = data.aws_subnet.ipsec_subnet.id
    instance_type   = var.ipsec_instance_type
    key_name        = var.ipsec_key_name
    iam_instance_profile = aws_iam_instance_profile.ha-ipsec-role.name
    security_groups = [aws_security_group.ipsec_sg.id]
    source_dest_check = false
    tags = {
        Name = "HA-IPSec-A"
    }
    user_data = file(var.ipsec_init_script)
}

resource "aws_instance" "HA-IPSec-B" {
    depends_on = [aws_iam_instance_profile.ha-ipsec-role]
    ami             = data.aws_ami.ubuntu.id
    subnet_id       = data.aws_subnet.ipsec_subnet.id
    instance_type   = var.ipsec_instance_type
    key_name        = var.ipsec_key_name
    iam_instance_profile = aws_iam_instance_profile.ha-ipsec-role.name
    security_groups = [aws_security_group.ipsec_sg.id]
    source_dest_check = false
    tags = {
        Name = "HA-IPSec-B"
    }
    user_data = file(var.ipsec_init_script)
}

resource "aws_eip" "HA-IPSec-A" {
  domain = "vpc"
  instance = aws_instance.HA-IPSec-A.id
}

resource "aws_eip" "HA-IPSec-B" {
  domain = "vpc"
  instance = aws_instance.HA-IPSec-B.id
}

resource "aws_sns_topic" "ha_ipsec_update" {
  name = "ha_ipsec_update"
}

# save the instance information
resource "aws_ssm_parameter" "ha-ipsec-a" {
  name  = "/ha-ipsec/${aws_instance.HA-IPSec-A.id}"
  type  = "String"
  value = <<-EOF
    { 
        "peer" : "${aws_instance.HA-IPSec-B.id}",
        "status" : "BACKUP",
        "ip" : "${aws_instance.HA-IPSec-A.private_ip}",
        "eni" : "${aws_instance.HA-IPSec-A.primary_network_interface_id}",
        "sns" : "${aws_sns_topic.ha_ipsec_update.arn}"
    }
    EOF
}

resource "aws_ssm_parameter" "ha-ipsec-b" {
  name  = "/ha-ipsec/${aws_instance.HA-IPSec-B.id}"
  type  = "String"
  value = <<-EOF
    { 
        "peer" : "${aws_instance.HA-IPSec-A.id}",
        "status" : "MASTER",
        "ip" : "${aws_instance.HA-IPSec-B.private_ip}",
        "eni" : "${aws_instance.HA-IPSec-B.primary_network_interface_id}",
        "sns" : "${aws_sns_topic.ha_ipsec_update.arn}"
    }
    EOF
}
