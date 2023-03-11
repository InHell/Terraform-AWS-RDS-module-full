# block to make some random string for a name's
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  lower   = true
}

locals {
  name   = "${var.environment}-mssql-rds-${random_string.suffix.result}"
  region = var.region
  tags = {
    environment = "${var.environment}"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.18.1"

  name = local.name
  cidr = "10.99.0.0/18"

  azs              = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets   = ["10.99.0.0/24", "10.99.1.0/24", "10.99.2.0/24"]
  private_subnets  = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]
  database_subnets = ["10.99.7.0/24", "10.99.8.0/24", "10.99.9.0/24"]

  create_database_subnet_group = true
  # also need for worldwire , subnets have no out route, only cidr rout 10x. so add this (c) Dsv
  enable_dns_support                     = true
  enable_dns_hostnames                   = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = true

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.16.2"

  name        = local.name
  description = "SqlServer security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  # access from local-vps block inside network 10.99.X.X/18
  ingress_with_cidr_blocks = [
    {
      from_port   = 1433
      to_port     = 1433
      protocol    = "tcp"
      description = "SqlServer inbound access from LAN/VPC"
      #cidr_blocks = module.vpc.vpc_cidr_block
      cidr_blocks = "10.99.0.0/18"
    },

  #this is optional secure block if you have white ip list of app-office thats need acces to rds usti this block only  
  #  {
  #    from_port   = 1433
  #    to_port     = 1433
  #    protocol    = "tcp"
  #    description = "SqlServer inbound access from WWW on non-standart port SQL"
  #    type correct your white ip bellow ! 
  #    cidr_blocks = "100.100.200.200/32"
  #  },
    
    
    # try to use white-list's for secure conection at port 1433 , or change 1433 port to non-standart cuz in time will be login attempts from bots 
    {
      from_port   = 1433
      to_port     = 1433
      protocol    = "tcp"
      description = "SqlServer inbound access from WWW on non-standart port SQL"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  # egress
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "Allow outbound access to WAN"
      cidr_blocks = module.vpc.vpc_cidr_block
      #cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = local.tags
}

module "rds_mssql" {
  source  = "terraform-aws-modules/rds/aws"
  version = "5.1.1"

  identifier = local.name

  engine               = var.engine
  engine_version       = var.engine_version
  family               = var.family
  major_engine_version = var.major_engine_version
  instance_class       = var.instance_class

  allocated_storage     = var.stor_size
  max_allocated_storage = var.max_stor_size

  # Encryption at rest is not available for DB instances running SQL Server Express Edition
  storage_encrypted = false
  # this is access for db from world enable
  publicly_accessible    = true
  #this is little trap ;) set false if whant to user your password
  create_random_password = false
  username               = var.username
  password               = var.pass

  port = 1433

  multi_az               = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["error"]
  create_cloudwatch_log_group     = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false


  create_monitoring_role = true
  monitoring_interval    = 60
  monitoring_role_name   = "${var.environment}-mssql-rds-role-${random_string.suffix.result}"


  create_db_parameter_group = false
  license_model             = "license-included"
  timezone                  = "GMT Standard Time"
  character_set_name        = "Latin1_General_CI_AS"
  # automate some magic, make policy, insert json rules and arn to make iaac for S3 option group with backup permission only on -backup- root name of bucked
  #in
  create_db_option_group = false
  option_group_name      = aws_db_option_group.rds_db_option_group.name
  options                = aws_db_option_group.rds_db_option_group.option

  tags = local.tags
}

resource "aws_db_option_group" "rds_db_option_group" {
  name                     = "${var.environment}-rds-db-option-group"
  option_group_description = "backups for DB"
  engine_name              = var.engine
  major_engine_version     = var.major_engine_version


  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"

    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.rds_backup_iam_role.arn
    }
  }
}

#------------------------- IAM roles and policy part for Option Group --------------------------------
data "aws_iam_policy_document" "rds_backup_iam_policy_document" {
  statement {
    sid = "1"

    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
      "s3:GetObjectMetaData",
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]

    resources = [
      "arn:aws:s3:::rds-backup-*",
    ]
  }

  statement {
    actions = [
      "s3:*",
    ]

    resources = [
      "arn:aws:s3:::rds-backup-*",
      "arn:aws:s3:::rds-backup-*/*",
    ]
  }
}

resource "aws_iam_policy" "rds_backup_iam_policy" {
  name       = "${var.environment}-rds-backup-iam-policy"
  path       = "/"
  policy     = data.aws_iam_policy_document.rds_backup_iam_policy_document.json
  depends_on = [data.aws_iam_policy_document.rds_backup_iam_policy_document]

  tags = {
    environment = "${var.environment}"
  }
}

data "aws_iam_policy_document" "rds_backup_iam_assume_policy_document" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_backup_iam_role" {
  name               = "${var.environment}-rds-backup-iam-role"
  assume_role_policy = data.aws_iam_policy_document.rds_backup_iam_assume_policy_document.json
  depends_on         = [data.aws_iam_policy_document.rds_backup_iam_assume_policy_document]

  tags = {
    environment = "${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "rds_backup_iam_role" {
  role       = aws_iam_role.rds_backup_iam_role.name
  policy_arn = aws_iam_policy.rds_backup_iam_policy.arn
}

#FIXME: Replace acl = private to Grant model in future ++
resource "aws_s3_bucket" "rds_backup_bucket" {
  bucket = "rds-backup-${var.environment}-${var.aws_account_id}-${random_string.suffix.result}"
  acl    = "private"
  tags = {
    environment = "${var.environment}"
  }
}
