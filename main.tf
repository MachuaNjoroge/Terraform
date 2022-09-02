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


resource "aws_security_group" "jenkins_security_group" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.jenkins_vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.jenkins_vpc.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.jenkins_vpc.ipv6_cidr_block]
  }

  ingress {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.jenkins_vpc.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.jenkins_vpc.ipv6_cidr_block]
  }

  ingress {
    description      = "ssh from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.jenkins_vpc.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.jenkins_vpc.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "web_and_ssh_access"
  }
}

resource "aws_key_pair" "jenkins_auth" {
  key_name   = "dev_key"
  public_key = file("~/Terraform/Terraform/.ssh/dev_key.pub")
}


resource "aws_instance" "jenkins_master" {
  ami           = data.aws_ami.jenkings-ubuntu.id
  instance_type = "t2.micro"

  key_name               = aws_key_pair.jenkins_auth.id
  vpc_security_group_ids = [aws_security_group.jenkins_security_group.id]
  subnet_id              = aws_subnet.jenkins_subnet.id

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
  subnet_id   = aws_subnet.jenkins_subnet.id
  private_ips = ["10.20.0.10"]

  tags = {
    Name = "primary_network_interface"
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
  ami           = data.aws_ami.jenkings-ubuntu.id
  instance_type = "t2.micro"

  key_name               = aws_key_pair.jenkins_auth.id
  vpc_security_group_ids = [aws_security_group.jenkins_security_group.id]
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
