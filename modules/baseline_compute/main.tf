# EC2 + EBS

variable "baseline_tags" {
  type = map(string)
}
# ###############################################################################
# # 3.1) At the top of the file, look for the current Amazon Linux 2 AMI
# ###############################################################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    # values = ["amzn2-ami-hvm-2.0.*-x86_64-gp[23]"]
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2", "amzn2-ami-hvm-2.0.*-x86_64-gp3"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
}
# ###############################################################################
# # 4. EC2: 3 инстанса t3.micro
# ###############################################################################
resource "aws_instance" "baseline_ec2" {
  count         = 3
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  tags          = merge(var.baseline_tags, { Name = "baseline-ec2-${count.index + 1}" })
}
# ###############################################################################
# # 5. EBS: 50 GB gp3 volume (not mounted)
# ###############################################################################
resource "aws_ebs_volume" "baseline_ebs" {
  count             = 3
  availability_zone = aws_instance.this[count.index].availability_zone
  size              = 50
  type              = "gp3"
  tags              = merge(var.baseline_tags, { Name = "baseline-ebs-${count.index + 1}" })
}


