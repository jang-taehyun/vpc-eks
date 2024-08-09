terraform {
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

# vpc 정의
resource "aws_vpc" "this" {
    cidr_block = "10.10.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "eks-vpc"
    }
}

# IGW 생성, vpc와 IGW 연결
resource "aws_internet_gateway" "this" {
    vpc_id = aws_vpc.this.id

    tags = {
      Name = "eks-vpc-igw"
    }
}

# NATGW를 위한 탄력 IP 생성
resource "aws_eip" "this" {
    lifecycle {
        create_before_destroy = true    # 재생성 시, 먼저 새로운 Elastic IP를 하나 만들고 기존 것을 삭제
    }

    tags = {
      Name = "eks-vpc-eip"
    }
}

# public subnet 생성
resource "aws_subnet" "pub_sub1" {
    vpc_id = aws_vpc.this.id
    cidr_block = "10.10.10.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    map_public_ip_on_launch = true
    availability_zone = "ap-northeast-2a"

    tags = {
      Name = "eks-vpc-pub-sub1"
      Label = "test"
      "kubernetes.io/cluster/pri-cluster" = "owned"
      "kubernetes.io/role/elb" = "1"
    }

    depends_on = [ aws_internet_gateway.this ]
}

resource "aws_subnet" "pub_sub2" {
    vpc_id = aws_vpc.this.id
    cidr_block = "10.10.11.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    map_public_ip_on_launch = true
    availability_zone = "ap-northeast-2c"

    tags = {
      Name = "eks-vpc-pub-sub2"
      Label = "test"
      "kubernetes.io/cluster/pri-cluster" = "owned"
      "kubernetes.io/role/elb" = "1"
    }

    depends_on = [ aws_internet_gateway.this ]
}

# NATGW 생성
resource "aws_nat_gateway" "this" {
    allocation_id = aws_eip.this.id
    subnet_id = aws_subnet.pub_sub1.id

    tags = {
      Name = "eks-vpc-natgw"
      Label = "test"
    }

    lifecycle {
        create_before_destroy = true
    }

    depends_on = [ aws_eip.this, aws_subnet.pub_sub1 ]
}

# private subnet 생성
resource "aws_subnet" "pri_sub1" {
    vpc_id = aws_vpc.this.id
    cidr_block = "10.10.20.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2a"

    tags = {
      Name = "eks-vpc-pri_sub1"
      Label = "test"
      "kubernetes.io/cluster/pri-cluster" = "owned"
      "kubernetes.io/role/internal-elb" = "1"
    }

    depends_on = [ aws_nat_gateway.this ]
}

resource "aws_subnet" "pri_sub2" {
    vpc_id = aws_vpc.this.id
    cidr_block = "10.10.21.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2c"

    tags = {
      Name = "eks-vpc-pri-sub2"
      Label = "test"
      "kubernetes.io/cluster/pri-cluster" = "owned"
      "kubernetes.io/role/internal-elb" = "1"
    }

    depends_on = [ aws_nat_gateway.this ]
}

# public routing table 정의
resource "aws_route_table" "eks-vpc-pub-rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  route {
    cidr_block = "10.10.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "eks-vpc-pub-rt"
  }
}

# private routing table 정의
resource "aws_route_table" "eks-vpc-pri-rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.10.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "eks-vpc-pri-rt"
  }
}

# routing table과 subnet을 연결
resource "aws_route_table_association" "pub-rt-asso1" {
    subnet_id = aws_subnet.pub_sub1.id
    route_table_id = aws_route_table.eks-vpc-pub-rt.id

    depends_on = [ aws_subnet.pub_sub1, aws_route_table.eks-vpc-pub-rt ]
}

resource "aws_route_table_association" "pub-rt-asso2" {
    subnet_id = aws_subnet.pub_sub2.id
    route_table_id = aws_route_table.eks-vpc-pub-rt.id

    depends_on = [ aws_subnet.pub_sub2, aws_route_table.eks-vpc-pub-rt ]
}

resource "aws_route_table_association" "pri-rt-asso1" {
    subnet_id = aws_subnet.pri_sub1.id
    route_table_id = aws_route_table.eks-vpc-pri-rt.id

    depends_on = [ aws_subnet.pri_sub1, aws_route_table.eks-vpc-pri-rt ]
}

resource "aws_route_table_association" "pri-rt-asso2" {
    subnet_id = aws_subnet.pri_sub2.id
    route_table_id = aws_route_table.eks-vpc-pri-rt.id

    depends_on = [ aws_subnet.pri_sub2, aws_route_table.eks-vpc-pri-rt ]
}

# security group 생성
resource "aws_security_group" "eks-vpc-pub-sg" {
  vpc_id = aws_vpc.this.id
  name = "eks-vpc-pub-sg"

  tags = {
    Name = "eks-vpc-pub-sg"
  }
}

# security group의 ingress 규칙 설정
# HTTP ingress 허용
resource "aws_security_group_rule" "eks-vpc-http-ingress" {
  security_group_id = aws_security_group.eks-vpc-pub-sg.id

  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "TCP"
  cidr_blocks = [ "0.0.0.0/0" ]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [ aws_security_group.eks-vpc-pub-sg ]
}

# SSH ingress 허용
resource "aws_security_group_rule" "eks-vpc-ssh-ingress" {
  security_group_id = aws_security_group.eks-vpc-pub-sg.id

  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "TCP"
  cidr_blocks = [ "0.0.0.0/0" ]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [ aws_security_group.eks-vpc-pub-sg ]
}

# security group의 egress 규칙 설정
resource "aws_security_group_rule" "eks-vpc-all-egress" {
  security_group_id = aws_security_group.eks-vpc-pub-sg.id

  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [ "0.0.0.0/0" ]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [ aws_security_group.eks-vpc-pub-sg ]
}