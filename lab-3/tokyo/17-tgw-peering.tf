############################################
# Lab 3: Tokyo TGW Peering — Phase 3
# Accept peering request from São Paulo (Liberdade)
############################################

# Accept the peering request that SP created in Phase 2
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "shinjuku_accept_liberdade_peer01" {
  count = local.phase3_active ? 1 : 0

  transit_gateway_attachment_id = local.resolved_sp_peering_id

  tags = merge(local.tokyo_tags, {
    Name = "${local.tokyo_tgw_prefix}-accept-liberdade-peer01"
  })
}

# Static route to São Paulo via peering
resource "aws_ec2_transit_gateway_route" "shinjuku_to_saopaulo_static" {
  count = local.phase3_active ? 1 : 0

  destination_cidr_block         = local.resolved_sp_vpc_cidr # 10.76.0.0/16
  transit_gateway_attachment_id  = local.resolved_sp_peering_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shinjuku_rt01.id

  depends_on = [
    aws_ec2_transit_gateway_peering_attachment_accepter.shinjuku_accept_liberdade_peer01
  ]
}
