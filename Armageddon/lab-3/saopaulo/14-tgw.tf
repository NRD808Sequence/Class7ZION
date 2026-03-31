############################################
# Lab 3: São Paulo Transit Gateway (Liberdade Spoke)
# Secondary TGW for APPI-compliant cross-region connectivity
############################################

# Liberdade is São Paulo's Japanese town - local doctors, local compute, remote data
resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  description                     = "liberdade-tgw01 (Sao Paulo spoke)"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_tgw_prefix}-tgw01"
  })
}

# Liberdade attaches to its VPC - compute can now reach Tokyo legally, through the controlled corridor
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.liberdade_vpc01.id
  subnet_ids = [
    aws_subnet.liberdade_private_subnet01.id,
    aws_subnet.liberdade_private_subnet02.id
  ]

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_tgw_prefix}-attach-sp-vpc01"
  })
}

# Note: Using the default route table (default_route_table_association = "enable")
# The VPC attachment auto-associates and auto-propagates to the default RT.
# Custom route table, explicit association, and propagation removed to avoid
# conflict with the default RT auto-association.
