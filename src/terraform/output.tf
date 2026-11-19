output "ec2_public_ip" {
  value = aws_instance.devops.public_ip
}

output "ec2_public_dns" {
  value = aws_instance.devops.public_dns
}

output "vpc_id" {
  value = aws_vpc.main.id
}
