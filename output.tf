# Copyright 2024 ke.liu#foxmail.com

output "HA-IPSEC-A" {
    value = <<-EOF
       IP         = ${aws_eip.HA-IPSec-A.public_ip}
       PRIVATE-IP = ${aws_instance.HA-IPSec-A.private_ip}
    EOF
}

output "HA-IPSEC-B" {
    value = <<-EOF
       IP         = ${aws_eip.HA-IPSec-B.public_ip}
       PRIVATE-IP = ${aws_instance.HA-IPSec-B.private_ip}
    EOF
}

output "Security-Group" {
    value = aws_security_group.ipsec_sg.id
}

output "EC2-Role" {
    value = <<-EOF
        Role   = ${aws_iam_role.ha-ipsec-role.name}
    EOF
}

output "Parameter-Store" {
    value = <<-EOF
        ${aws_ssm_parameter.ha-ipsec-a.name}
        ${aws_ssm_parameter.ha-ipsec-b.name}
    EOF
}

output "Event-Notificatoin-SNS-Topoc" {
    value = aws_sns_topic.ha_ipsec_update.arn
}