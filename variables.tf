variable "region" {
  default = "us-east-1"
}

#recive var from main body of terraform tf 
variable "environment" {
  description = "environment"
  type        = string
}

variable "aws_account_id" {
  default = "*some id"
}

variable "engine" {
  default = "sqlserver-ex"
}

variable "engine_version" {
  default = "15.00.4153.1.v1"
}

variable "family" {
  default = "sqlserver-ex-15.0"
}

variable "major_engine_version" {
  default = "15.00"
}

variable "instance_class" {
  default = "db.t3.small"
}

variable "stor_size" {
  default = "20"
}

variable "max_stor_size" {
  default = "50"
}

variable "username" {
  default = "your_user_name"
}
#password, set your own 
variable "pass" {
  default = "12345678"
}

