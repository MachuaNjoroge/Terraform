resource "aws_vpc" "jenkins_vpc" {
  cidr_block = "10.20.0.0/16"

  tags = {
    "Name" = "jenkins_vpc"
  }
}

resource "aws_subnet" "jenkins_subnet" {
  vpc_id     = aws_vpc.jenkins_vpc.id
  cidr_block = "10.20.0.0/20"

  tags = {
    Name = "jenkins_subnet"
  }
}

resource "aws_internet_gateway" "jenkins_internet_gw" {
  vpc_id = aws_vpc.jenkins_vpc.id

  tags = {
    Name = "jenkins_internet_gw"
  }
}

resource "aws_route_table" "jenkins_route_table" {
  vpc_id = aws_vpc.jenkins_vpc.id

  tags = {
    Name = "jenkins_route_table"
  }
}

#Route all internet traffic to internet
resource "aws_route" "jenkins_route_table" {
  route_table_id         = aws_route_table.jenkins_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.jenkins_internet_gw.id
}

resource "aws_route_table_association" "jenkins_route_table_assoc" {
  subnet_id      = aws_subnet.jenkins_subnet.id
  route_table_id = aws_route_table.jenkins_route_table.id
}


resource "aws_security_group" "jenkins_master_security_group" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.jenkins_vpc.id

  ingress {
    description = "TLS to VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    #cidr_blocks restricts source. Setting only our VPC means that the instance is not available from internet
    #cidr_blocks = [aws_vpc.jenkins_vpc.cidr_block]
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP to VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #cidr_blocks = [aws_vpc.jenkins_vpc.cidr_block]
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh to VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    #Put cidr access to be you public IP and not 0.0.0.0/0 which means all IPs
    #cidr_blocks = [aws_vpc.jenkins_vpc.cidr_block]
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  lifecycle {
    # Necessary if changing 'name' or 'name_prefix' properties.
    create_before_destroy = true
  }

  tags = {
    Name = "web_and_ssh_access"
  }
}

resource "aws_key_pair" "jenkins_auth" {
  key_name   = "master_key"
  public_key = file("~/Terraform/Terraform/.ssh/master_key.pub")

  tags = {
    Name = "jenkins_master_keys"
  }
}


resource "aws_instance" "jenkins_master" {
  ami           = data.aws_ami.ubuntu_2004.id
  instance_type = "t2.micro"
  #vpc_security_group_ids can be specified in either network interface or aws instance but not both
  #vpc_security_group_ids = [aws_security_group.jenkins_master_security_group.id] 
  key_name = aws_key_pair.jenkins_auth.id
  #subnet_id              = aws_subnet.jenkins_subnet.id

  user_data = file("userdata.tpl")

  root_block_device {
    volume_size = 10
  }

  network_interface {
    network_interface_id = aws_network_interface.jenkins_master_network_interface.id
    device_index         = 0
  }

  tags = {
    Name = "jenkins-master"
  }
}


resource "aws_network_interface" "jenkins_master_network_interface" {
  subnet_id       = aws_subnet.jenkins_subnet.id
  private_ips     = ["10.20.0.10"]
  security_groups = [aws_security_group.jenkins_master_security_group.id]

  tags = {
    Name = "jenkins_master_network_interface"
  }
}

resource "aws_eip" "jenkins_eip" {
  vpc = true

  #instance                  = aws_instance.jenkins_master.id
  associate_with_private_ip = "10.20.0.10"
  depends_on                = [aws_internet_gateway.jenkins_internet_gw]
}


resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_master.id
  allocation_id = aws_eip.jenkins_eip.id
}

resource "aws_instance" "jenkins-builder1" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  iam_instance_profile        = aws_iam_instance_profile.jenkins_instance_profile.name
  associate_public_ip_address = "true"

  key_name               = aws_key_pair.builder-key-pair.id
  vpc_security_group_ids = [aws_security_group.jenkins_master_security_group.id]
  subnet_id              = aws_subnet.jenkins_subnet.id
  private_ip             = "10.20.0.11"

  user_data = file("builderdata.tpl")

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name = "jenkins_builder1"
  }

}

resource "aws_iam_role" "jenkins_ec2_access_role" {
  name               = "ec2-role"
  assume_role_policy = data.aws_iam_policy_document.builder-assume-role-policy.json
}

resource "aws_iam_policy" "jenkins_elastic_beanstalk_policy" {
  name        = "beanstalk_policy"
  description = "This policy grants AdministratorAccess-AWSElasticBeanstalk AWS built in policy"
  policy      = file("elasticbeanstalkpolicy.json")
}

resource "aws_iam_policy_attachment" "jenkins_beanstalk_policy_attachment" {
  name       = "jenkins_beanstalk_attachment"
  roles      = [aws_iam_role.jenkins_ec2_access_role.name]
  policy_arn = aws_iam_policy.jenkins_elastic_beanstalk_policy.arn
}

resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "instance_profile"
  role = aws_iam_role.jenkins_ec2_access_role.name
}

resource "aws_key_pair" "builder-key-pair" {
  key_name   = "builder_key"
  public_key = file("~/Terraform/Terraform/.ssh/builder_key.pub")

  tags = {
    Name = "jenkins_builder_keys"
  }
}

resource "aws_security_group" "jenkins_builder_security_group" {
  name        = "builder_security_group"
  description = "Allow connection to jenkins buider machines from master"
  vpc_id      = aws_vpc.jenkins_vpc.id

  ingress {
    description     = "Allow access from the jenkins_master security group"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.jenkins_master_security_group.id]
  }

  egress {
    description      = "Allow all egress traffic"
    to_port          = 0
    from_port        = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    # Necessary if changing 'name' or 'name_prefix' properties.
    create_before_destroy = true
  }

  tags = {
    Name = "buider_security_group"
  }
}