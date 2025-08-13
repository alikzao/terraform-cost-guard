# два RDS

variable "baseline_tags" { type = map(string) }

resource "aws_db_instance" "mysql" {
  identifier          = "baseline-mysql"
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "ChangeMe123!"
  skip_final_snapshot = true
  publicly_accessible = false
  tags                = var.baseline_tags
}

resource "aws_db_instance" "postgres" {
  identifier          = "baseline-postgres"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "baseline_user"
  password            = "ChangeMe123!"
  skip_final_snapshot = true
  publicly_accessible = false
  tags                = var.baseline_tags
}
