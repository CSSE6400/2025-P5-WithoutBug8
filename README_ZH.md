## week6实践课程笔记

### 本周的任务

在 AWS 上用 Terraform 部署数据库和容器，具体需要实现以下的功能

1. 使用 Terraform 部署一个 RDS（PostgreSQL）数据库
2. 用 ECS（Elastic Container Service）部署 TaskOverflow 容器
3. 可选：把你自己构建的 Docker 镜像上传到 ECR（Elastic Container Registry）

### 具体内容的分析

1. AWS创建数据库，根据week6的教程可以一步一步的来这个是没有问题的,但是这里还是想补充一些细节

   | **名称** | **中文解释** | **用途**                                              | **举例**       |
   | -------- | :----------- | ----------------------------------------------------- | -------------- |
   | provider | 提供者       | 告诉 Terraform 你想操控哪个平台（AWS, Docker, etc.）  | 我要用 AWS     |
   | resource | 资源         | 你想 **创建/管理** 的东西（服务器、数据库、安全组等） | 创建一个数据库 |
   | data     | 数据源       | 从现有系统里**读取**已有的东西（不会创建新东西）      | 查找已有的 VPC |

   他们之间可以互相调用,具体的格式为`[类型].[名字].[属性]`

2. 使用Terraform来操纵数据库，具体的代码分析如下

   ```python
   # 1.先定义本地变量，这个就是类似于一个账号用于连接数据库，所以可以进行任意的更改
   locals {
     database_username = "administrator"
     database_password = "foobarbaz" # This is bad!
   }
   
   # 2. 创建AWS RDS数据库instance
   resource "aws_db_instance" "taskoverflow_database" {
     allocated_storage       = 20
     max_allocated_storage   = 1000
     engine                  = "postgres"
     engine_version          = "17"
     instance_class          = "db.t3.micro"	  # 数据库性能等级，越大的越贵
     db_name                 = "todo"
     username                = local.database_username
     password                = local.database_password
     parameter_group_name    = "default.postgres17"
     skip_final_snapshot     = true
     vpc_security_group_ids  = [aws_security_group.taskoverflow_database.id]
     # 这个详细的讲解一下：aws_security_group.taskoverflow_database是调用下面的resource中的aws_security_group，然后是resource.name => (taskoverflow_database)，最后因为AWS资源都会有一个唯一的id，所以再.id
     publicly_accessible     = true		# 允许公网访问
   
     tags = {
       Name = "taskoverflow_database"	# 标记，方便AWS控制台识别资源
     }
   }
   
   # 3. 配置数据库的安全组(防火墙)
   resource "aws_security_group" "taskoverflow_database" {
     name        = "taskoverflow_database"
     description = "Allow inbound Postgresql traffic"
   	# 允许所有的IP(0.0.0.0/0)通过5432端口访问数据库
     ingress {
       from_port   = 5432
       to_port     = 5432
       protocol    = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }
   	# 允许数据库instance访问外部网络，开放所有端口和协议;也就是可以发往任何IP
     egress {
       from_port       = 0
       to_port         = 0
       protocol        = "-1"
       cidr_blocks     = ["0.0.0.0/0"]
       ipv6_cidr_blocks = ["::/0"]
     }
   
     tags = {
       Name = "taskoverflow_database"
     }
   }
   ```

3. ESC容器部署: 

   - 根据以往的经验,一般来说使用服务器,一般都把应用部署到EC2上,但是EC2有很多的局限性,比如需要手动操作,自动分配CPU/RAM......
   - 所以我们在这里引入ECS. ECS是容器级别的服务部署平台, Fargate是自动运行容器,不需要手动配置服务器,省去了很多的烦心的事情

   ```python
   # Terraform部署一个叫TaskOverflow的Flask Web应用(容器),运行在ECS+Fargate上,并连接我的RDS数据库
   # 1. 获取现有的资源
   data "aws_iam_role" "lab" {
     name = "LabRole"
   }
   # 2. 读取IAM现有的角色LabRole,这个角色有权运行任务（执行容器任务）
   data "aws_vpc" "default" {
     default = true
   }
   # 3. 获取当前 AWS 账户的默认 VPC，用于放 ECS 容器和网络
   data "aws_subnets" "private" {
     filter {
       name = "vpc-id"
       values = [data.aws_vpc.default.id]
     }
   }
   # 4. 声明 AWS Provider
   provider "aws" {
     region = "us-east-1"
     shared_credentials_files = ["./credentials"]
   }
   # 5. 创建 ECS 集群
   resource "aws_ecs_cluster" "taskoverflow" {
     name = "taskoverflow"
   }
   # 6. 定义 ECS 任务（container specification）
   resource "aws_ecs_task_definition" "taskoverflow" {
     ...
     container_definitions = <<DEFINITION
     [
       {
         "name": "todo",
         "image": "${local.image}",
         ...
       }
     ]
     DEFINITION
   }
   # 7. 创建ECS服务
   resource "aws_ecs_service" "taskoverflow" {
     ...
     launch_type     = "FARGATE"
   }
   # 8. 配置安全组
   resource "aws_security_group" "taskoverflow" {
     ...
   }
   ```

   

4. 自定义镜像到 AWS ECR

​	ECR(Elastic Container Registry)镜像托管仓库,这部分的内容是吧本机的镜像上传到ECR中托管

```python
# 1. 配置两个Provider
required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
        docker = {
            source = "kreuzwerker/docker"
            version = "3.0.2"
        }
    }
# 2. 认证Docker访问AWS ECR
data "aws_ecr_authorization_token" "ecr_token" {}

provider "docker" {
  registry_auth {
    address  = ...
    username = ...
    password = ...
  }
}
# 3. 创建一个AWS ECR仓库
resource "aws_ecr_repository" "taskoverflow" {
  name = "taskoverflow"
}
# 4. 在本地构建镜像并上传
resource "docker_image" "taskoverflow" {
  name = "${aws_ecr_repository.taskoverflow.repository_url}:latest"
  build {
    context = "."
  }
}

resource "docker_registry_image" "taskoverflow" {
  name = docker_image.taskoverflow.name
}
```

