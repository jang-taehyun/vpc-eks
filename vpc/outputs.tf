output "eks-vpc-id" {
  # eks-vpc-id 라는 key에 aws_vpc.this.id가 들어갈 예정
  # key : eks-vpc-id
  # value : aws_vpc.this.id
  value = aws_vpc.this.id
}

output "pri-sub1-id" {
  value = aws_subnet.pri_sub1.id
}

output "pri-sub2-id" {
  value = aws_subnet.pri_sub2.id
}

output "pub-sub1-id" {
  value = aws_subnet.pub_sub1.id
}

output "pub-sub2-id" {
  value = aws_subnet.pub_sub2.id
}