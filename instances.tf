resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name   = "tsv_key"
  public_key = tls_private_key.ssh.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.ssh.private_key_pem}' > ./${var.generated_key_name}.pem"
  }

  provisioner "local-exec" {
    command = "chmod 400 ./${var.generated_key_name}.pem"
  }
}


resource "aws_instance" "mysql_ec2instance" {
  instance_type           = "t2.micro"
  ami                     = "ami-0d527b8c289b4af7f"
  subnet_id               = aws_subnet.private_subnet.id
  security_groups         = [aws_security_group.securitygroup.id]
  key_name                = aws_key_pair.ssh.key_name
  private_ip              = var.db_private_ips
  disable_api_termination = false
  ebs_optimized           = false
  root_block_device {
    volume_size = "10"
  }

  tags = {
    "Name" = "mysql ec2 instanse private subnet"
  }
}

resource "aws_instance" "bastion_instance" {
  instance_type           = "t2.micro"
  ami                     = "ami-0d527b8c289b4af7f"
  subnet_id               = aws_subnet.public-subnet.id
  security_groups         = [aws_security_group.securitygroup.id]
  key_name                = aws_key_pair.ssh.key_name
  disable_api_termination = false
  ebs_optimized           = false
  root_block_device {
    volume_size = "10"
  }

  depends_on = [aws_instance.mysql_ec2instance, ]

  tags = {
    "Name" = "bastion ec2 instanse public subnet"
  }
}

resource "null_resource" "null_cluster" {

  provisioner "local-exec" {
    #command = "echo '[mysql]\nserver1 ansible_host=${aws_instance.mysql_ec2instance.private_ip}\n[mysql:vars]\nansible_ssh_user=ubuntu\nansible_ssh_private_key_file=~/ansible/${var.generated_key_name}.pem' > hosts.txt"
    command = "echo '[mysql]\nserver1 ansible_host=${aws_instance.mysql_ec2instance.private_ip}\n[mysql:vars]\nansible_ssh_user=ubuntu\nansible_ssh_private_key_file=~/ansible/${var.generated_key_name}.pem' > hosts.txt"
    #ansible_ssh_common_args= '-o ProxyCommand="ssh -W %h:%p -q ubuntu@${aws_eip.bastion_eip.public_ip} -i ~/Work/RTFM/Bitbucket/aws-credentials/rtfm-dev.pem"'
  }

  provisioner "file" {
    source      = "/home/ubuntu/ansible"
    destination = "/home/ubuntu/"
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_eip.bastion_eip.public_ip
      private_key = file("./${var.generated_key_name}.pem")
    }
  }

  provisioner "remote-exec" {
    inline = ["chmod 400 ./ansible/${var.generated_key_name}.pem", "sudo apt update -y"]
   # inline = ["chmod 400 ./ansible/${var.generated_key_name}.pem", "sudo apt update -y", "sudo apt install ansible -y", "ansible-galaxy collection install community.mysql", "export ANSIBLE_HOST_KEY_CHECKING=False", "ansible-playbook ./ansible/p_book.yml -i ./ansible/hosts.txt"]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_eip.bastion_eip.public_ip
      private_key = file("./${var.generated_key_name}.pem")
    }
 
  }

#  provisioner "local-exec" {
#      command = "ansible-playbook p_book.yml" 
#    }
# provisioner "remote-exec" {
#     inline = ["sudo apt update", "sudo apt install python3 -y", "echo Done!", "echo Done! >> file.txt"]
#     connection {
#       type        = "ssh"
#       user        = "ubuntu"
#       host        = aws_instance.mysql_ec2instance.private_ip
#       private_key = file("./${var.generated_key_name}.pem")

#        bastion_host = aws_eip.bastion_eip.public_ip
#        bastion_user = "ubuntu"
#        bastion_private_key = file("./${var.generated_key_name}.pem")
#     }
# }

# provisioner "local-exec" {
#      command = "ansible-playbook p_book.yml" 
#    }


    depends_on = [aws_instance.bastion_instance, aws_instance.mysql_ec2instance, ]

}


# provisioner "remote-exec" {
#     inline = ["sudo apt update", "sudo apt install python3 -y", "echo Done!", "echo Done! >> file.txt"]
#     connection {
#       type        = "ssh"
#       user        = "ubuntu"
#       host        = aws_instance.mysql_ec2instance.private_ip
#       private_key = file("./${var.generated_key_name}.pem")

#        bastion_host = aws_eip.bastion_eip.public_ip
#        bastion_user = "ubuntu"
#        bastion_private_key = file("./${var.generated_key_name}.pem")
#     }
# }

# provisioner "local-exec" {
#     command = "ansible-playbook p_book.yml" 
#   }

resource "aws_ecs_cluster" "ecs-cluster" {
  name = "tsv-Cluster"
}

resource "aws_ecs_task_definition" "task-def" {
  family                   = var.family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory

  
  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "tsv1982/petclinic_01",
    "memory": ${var.fargate_memory},
    "name": "${var.family}",
    "networkMode": "awsvpc", 
    "environment": ${jsonencode(var.task_envs)},
    "portMappings": [
      {
        "containerPort": ${var.container_port},
        "hostPort": ${var.container_port}
      }
    ]
  }
]
DEFINITION
 depends_on = [aws_instance.bastion_instance, aws_instance.mysql_ec2instance,]
}

# resource "aws_ecs_task_definition" "data_dog" {
#   family                   = var.family
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "1024"
#   container_definitions = <<DEFINITION
# [
#   {
#     "cpu": 100,
#     "image": "gcr.io/datadoghq/agent:latest",
#     "memory": 256,
#     "name": "datadog-agent"
#   }
# ]
# DEFINITION
#  depends_on = [aws_instance.bastion_instance, aws_instance.mysql_ec2instance,]
# }


resource "aws_ecs_service" "service" {
  name            = "${var.stack}-Service"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.task-def.arn
  desired_count   = var.task_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.securitygroup.id]
    subnets          = aws_subnet.public-subnet.*.id
    assign_public_ip = true
  }
}

# resource "aws_ecs_service" "data_dog_service" {
#   name            = "${var.stack}-Service"
#   cluster         = aws_ecs_cluster.ecs-cluster.id
#   task_definition = aws_ecs_task_definition.data_dog.arn
#   desired_count   = var.task_count
#   launch_type     = "FARGATE"

#   network_configuration {
#     security_groups  = [aws_security_group.securitygroup.id]
#     subnets          = aws_subnet.public-subnet.*.id
#     assign_public_ip = true
#   }
# }


  