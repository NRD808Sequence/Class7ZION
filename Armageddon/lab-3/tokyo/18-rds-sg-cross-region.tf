############################################
# Lab 3: RDS Cross-Region Security Group Rule — Phase 3
# Tokyo's vault opens only to approved clinics — Liberdade gets DB access
############################################

# Allow MySQL (3306) from São Paulo VPC CIDR via TGW
resource "aws_security_group_rule" "shinjuku_rds_ingress_from_liberdade01" {
  count = local.phase3_active ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.chewbacca_rds_sg01.id
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = [local.resolved_sp_vpc_cidr] # 10.76.0.0/16
  description       = "Allow MySQL from Sao Paulo VPC via TGW - APPI compliant cross-region"
}
