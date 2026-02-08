############################################
# Lab 3: São Paulo TGW Peering REQUEST to Tokyo
# Reversed from monolith: SP requests, Tokyo accepts in Phase 3
############################################

# Liberdade opens a corridor request to Shinjuku
# SP knows Tokyo TGW ID from remote state
resource "aws_ec2_transit_gateway_peering_attachment" "liberdade_to_shinjuku_peer01" {
  transit_gateway_id      = aws_ec2_transit_gateway.liberdade_tgw01.id
  peer_region             = "ap-northeast-1"
  peer_transit_gateway_id = local.tokyo_tgw_id

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_tgw_prefix}-to-shinjuku-peer01"
  })
}

# Static route to Tokyo via peering
# NOTE: Cannot be created until Tokyo accepts the peering in Phase 3.
# After Phase 3 acceptance, re-run `terraform apply` in saopaulo/ to create this route.
resource "aws_ec2_transit_gateway_route" "liberdade_to_tokyo_static" {
  count                          = 0 # Set to 1 after Tokyo accepts peering in Phase 3
  destination_cidr_block         = local.tokyo_vpc_cidr # 10.75.0.0/16
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.liberdade_to_shinjuku_peer01.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.liberdade_tgw01.association_default_route_table_id
}
