variable "ami_id" { }
variable "subnet_id" { }
variable "vpc_id" { }

resource "tls_private_key" "keypair" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "keypair" {
  key_name = "example"
  public_key = tls_private_key.keypair.public_key_openssh
}

data "http" "provisoner_ip" {
  url = "http://icanhazip.com"
}

resource "aws_security_group" "ssh" {
  vpc_id = var.vpc_id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "${chomp(data.http.provisoner_ip.body)}/32" ]
  }
}

resource "aws_instance" "instance" {
  ami = var.ami_id
  instance_type = "t3.micro"
  subnet_id = var.subnet_id
  security_groups = [ aws_security_group.ssh.id ]
  associate_public_ip_address = true
  key_name = aws_key_pair.keypair.key_name
  user_data = file("${path.root}/user_data.sh")
}

output "private_key" {
  value = tls_private_key.keypair.private_key_pem
}

output "public_key" {
  value = tls_private_key.keypair.public_key_pem
}

output "ip_address" {
  value = aws_instance.instance.public_ip
}
