#Kubernetes Provider
provider "kubernetes" {}

# AWS Provider
provider "aws" {
  profile = "terraform-user"
  region  = "ap-south-1"
}
# VPC data soruce
data "aws_vpc" "def_vpc" {
  default = true
}

# Subnet data source
data "aws_subnet_ids" "vpc_sub" {
  vpc_id = data.aws_vpc.def_vpc.id
}
# Security Group for DB
resource "aws_security_group" "allow_data_in_db" {
  name        = "allow_db"
  description = "mysql access"
  vpc_id      = data.aws_vpc.def_vpc.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_wp_in_db"
  }
}

# subnet group for DB
resource "aws_db_subnet_group" "sub_ids" {
  name       = "main"
  subnet_ids = data.aws_subnet_ids.vpc_sub.ids

  tags = {
    Name = "DB subnet group"
  }
}

# DB Instances
resource "aws_db_instance" "wp_db" {
  engine                 = "mysql"
  engine_version         = "5.7"
  identifier             = "wordpress-db"
  username               = "admin"
  password               = "dbpass@12X"
  instance_class         = "db.t2.micro"
  storage_type           = "gp2"
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.sub_ids.id
  vpc_security_group_ids = [aws_security_group.allow_data_in_db.id]
  publicly_accessible    = true
  name                   = "wpdb"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
}

#deployment
resource "kubernetes_deployment" "wordpress_deploy" {
    depends_on = [
    aws_db_instance.wp_db
    ]
  metadata {
    name = "wordpress"
    labels = {
      app = "wordpress"
    }
  }
  spec {
    selector {
      match_labels = {
        app = "wordpress"
      }
    }
    template {
      metadata {
        labels = {
          app = "wordpress"
        }
      }
      spec {
        container {
          image = "wordpress"
          name  = "wordpress-pod"
          env {
            name = "WORDPRESS_DB_HOST"
            value = aws_db_instance.wp_db.endpoint
            }
          env {
            name = "WORDPRESS_DB_DATABASE"
            value = aws_db_instance.wp_db.name 
            }
          env {
            name = "WORDPRESS_DB_USER"
            value = aws_db_instance.wp_db.username
            }
          env {
            name = "WORDPRESS_DB_PASSWORD"
            value = aws_db_instance.wp_db.password
          }
          port {
        container_port = 80
          }
        }
      }
    }
  }
}

#service 
resource "kubernetes_service" "wordpress_service" {
    depends_on = [
    kubernetes_deployment.wordpress_deploy,
  ]
  metadata {
    name = "wp-service"
  }
  spec {
    selector = {
      app = "wordpress"
    }
    port {
      port = 80
      target_port = 80
      node_port = 30888
    }

    type = "NodePort"
  }
}