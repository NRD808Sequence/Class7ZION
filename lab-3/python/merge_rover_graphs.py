#!/usr/bin/env python3
"""
merge_rover_graphs.py
Merges Tokyo and Sao Paulo terraform graph DOT files into a single
combined multi-region graph with cross-region edges.

Usage:
    python3 merge_rover_graphs.py
"""

import re
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
LAB3 = Path(__file__).resolve().parent.parent          # lab-3/
TOKYO_DOT   = LAB3 / "tokyo"    / "tokyo_graph.dot"
SP_DOT      = LAB3 / "saopaulo" / "saopaulo_graph.dot"
OUT_DOT     = LAB3 / "combined_graph.dot"
OUT_SVG     = LAB3 / "combined_graph.svg"
GRAPHVIZ    = Path("/opt/homebrew/bin/dot")

# ---------------------------------------------------------------------------
# Filtering configuration
# ---------------------------------------------------------------------------
# Nodes to always SKIP (noise)
SKIP_PATTERNS = [
    re.compile(r'provider\['),                                  # provider nodes
    re.compile(r'^var\.'),                                      # var.* nodes
    re.compile(r'^output\.'),                                   # output.* nodes
    re.compile(r'^data\.aws_caller_identity'),                  # data.aws_caller_identity
    re.compile(r'^data\.aws_region'),                           # data.aws_region
    re.compile(r'^data\.aws_cloudfront_cache_policy'),          # data.aws_cloudfront_cache_policy.*
    re.compile(r'^data\.aws_cloudfront_origin_request_policy'), # data.aws_cloudfront_origin_request_policy.*
    re.compile(r'\(close\)'),                                   # anything with (close)
    re.compile(r'^root$'),                                      # [root] root
]

# Locals to KEEP (cross-region bridge locals) -- all others are filtered
KEEP_LOCALS = {
    "local.phase3_active",
    "local.resolved_sp_alb_dns",
    "local.resolved_sp_origin_fqdn",
    "local.resolved_sp_peering_id",
    "local.resolved_sp_vpc_cidr",
    "local.tokyo_tgw_id",
    "local.tokyo_vpc_cidr",
    "local.origin_secret",
}


def clean_id(raw_id: str) -> str:
    """Strip [root] prefix and (expand) suffix from a node id."""
    s = raw_id.strip()
    if s.startswith("[root] "):
        s = s[7:]
    if s.endswith(" (expand)"):
        s = s[:-9]
    return s


def should_skip(clean: str) -> bool:
    """Return True if a cleaned node id should be filtered out."""
    for pat in SKIP_PATTERNS:
        if pat.search(clean):
            return True
    # Filter local.* EXCEPT the ones we want to keep
    if clean.startswith("local.") and clean not in KEEP_LOCALS:
        return True
    return False


# ---------------------------------------------------------------------------
# DOT parser -- just enough for terraform graph output
# ---------------------------------------------------------------------------
NODE_RE = re.compile(
    r'^\s*"([^"]+)"\s*\[(.+)\]\s*$'
)
EDGE_RE = re.compile(
    r'^\s*"([^"]+)"\s*->\s*"([^"]+)"\s*$'
)


def parse_dot(path: Path):
    """Return (nodes: dict[raw_id -> attr_str], edges: list[(src, dst)])."""
    nodes: dict[str, str] = {}
    edges: list[tuple[str, str]] = []
    with open(path) as fh:
        for line in fh:
            m = NODE_RE.match(line)
            if m:
                nodes[m.group(1)] = m.group(2)
                continue
            m = EDGE_RE.match(line)
            if m:
                edges.append((m.group(1), m.group(2)))
    return nodes, edges


def node_shape(clean_id_str: str) -> str:
    """Determine shape and style for a node."""
    if clean_id_str.startswith("data."):
        return 'shape="box", style="dashed"'
    return 'shape="box"'


def quote(s: str) -> str:
    """Wrap a string in DOT double-quotes."""
    return f'"{s}"'


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"Reading Tokyo graph:    {TOKYO_DOT}")
    print(f"Reading Sao Paulo graph: {SP_DOT}")

    t_nodes, t_edges = parse_dot(TOKYO_DOT)
    s_nodes, s_edges = parse_dot(SP_DOT)

    # Clean and filter nodes
    # prefix every node id with region tag to avoid collisions
    # (e.g. data.aws_route53_zone.chewbacca_zone exists in both)

    def build_region(raw_nodes, raw_edges, prefix):
        """Return filtered (nodes_dict, edges_list) with prefixed clean ids."""
        clean_nodes = {}   # prefixed_clean_id -> clean_id (for label)
        for raw_id in raw_nodes:
            c = clean_id(raw_id)
            if should_skip(c):
                continue
            pid = f"{prefix}_{c}"
            clean_nodes[pid] = c
        # Build a set of surviving raw->prefixed mappings
        raw_to_prefixed = {}
        for raw_id in raw_nodes:
            c = clean_id(raw_id)
            if not should_skip(c):
                raw_to_prefixed[raw_id] = f"{prefix}_{c}"
        # Filter edges
        kept_edges = []
        for src, dst in raw_edges:
            if src in raw_to_prefixed and dst in raw_to_prefixed:
                kept_edges.append((raw_to_prefixed[src], raw_to_prefixed[dst]))
        return clean_nodes, kept_edges

    tokyo_nodes, tokyo_edges = build_region(t_nodes, t_edges, "tokyo")
    sp_nodes, sp_edges = build_region(s_nodes, s_edges, "sp")

    # Build the combined DOT
    lines = []
    lines.append('digraph lab3_multiregion {')
    lines.append('    rankdir=LR;')
    lines.append('    fontname="Helvetica";')
    lines.append('    fontsize=14;')
    lines.append('    label="Lab 3: Multi-Region Terraform Graph \\u2014 Chewbacca (Tokyo) + Liberdade (SP)";')
    lines.append('    labelloc=t;')
    lines.append('    node [fontname="Helvetica", fontsize=10];')
    lines.append('    edge [fontsize=8];')
    lines.append('    compound=true;')
    lines.append('    newrank=true;')
    lines.append('')

    # -- Tokyo subgraph --
    lines.append('    subgraph cluster_tokyo {')
    lines.append('        label="Tokyo (ap-northeast-1) \\u2014 chewbacca/shinjuku";')
    lines.append('        style=filled;')
    lines.append('        color="#D6EAF8";')
    lines.append('        fillcolor="#D6EAF8";')
    lines.append('        fontname="Helvetica";')
    lines.append('        fontsize=12;')
    lines.append('')
    for pid, label in sorted(tokyo_nodes.items()):
        shape = node_shape(label)
        lines.append(f'        {quote(pid)} [label={quote(label)}, {shape}];')
    lines.append('')
    for src, dst in tokyo_edges:
        lines.append(f'        {quote(src)} -> {quote(dst)};')
    lines.append('    }')
    lines.append('')

    # -- Sao Paulo subgraph --
    lines.append('    subgraph cluster_saopaulo {')
    lines.append('        label="S\\u00e3o Paulo (sa-east-1) \\u2014 liberdade";')
    lines.append('        style=filled;')
    lines.append('        color="#D5F5E3";')
    lines.append('        fillcolor="#D5F5E3";')
    lines.append('        fontname="Helvetica";')
    lines.append('        fontsize=12;')
    lines.append('')
    for pid, label in sorted(sp_nodes.items()):
        shape = node_shape(label)
        lines.append(f'        {quote(pid)} [label={quote(label)}, {shape}];')
    lines.append('')
    for src, dst in sp_edges:
        lines.append(f'        {quote(src)} -> {quote(dst)};')
    lines.append('    }')
    lines.append('')

    # -- Cross-region edges --
    cross_style = 'color="red", style="bold,dashed", penwidth=2.0'

    cross_edges = [
        # SP peering attachment -> Tokyo TGW (TGW Peering REQUEST)
        (
            "sp_aws_ec2_transit_gateway_peering_attachment.liberdade_to_shinjuku_peer01",
            "tokyo_aws_ec2_transit_gateway.shinjuku_tgw01",
            "TGW Peering REQUEST",
        ),
        # Tokyo peering accepter -> SP peering attachment (TGW Peering ACCEPT)
        (
            "tokyo_aws_ec2_transit_gateway_peering_attachment_accepter.shinjuku_accept_liberdade_peer01",
            "sp_aws_ec2_transit_gateway_peering_attachment.liberdade_to_shinjuku_peer01",
            "TGW Peering ACCEPT",
        ),
        # SP remote_state.tokyo -> Tokyo TGW (Remote State: tgw_id)
        (
            "sp_data.terraform_remote_state.tokyo",
            "tokyo_aws_ec2_transit_gateway.shinjuku_tgw01",
            "Remote State: tgw_id",
        ),
        # SP remote_state.tokyo -> Tokyo VPC (Remote State: vpc_cidr)
        (
            "sp_data.terraform_remote_state.tokyo",
            "tokyo_aws_vpc.chewbacca_vpc01",
            "Remote State: vpc_cidr",
        ),
        # SP remote_state.tokyo -> Tokyo random_password (Remote State: origin_secret)
        (
            "sp_data.terraform_remote_state.tokyo",
            "tokyo_random_password.chewbacca_origin_header_value01",
            "Remote State: origin_secret",
        ),
        # Tokyo remote_state.saopaulo -> SP ALB (Remote State: alb_dns)
        (
            "tokyo_data.terraform_remote_state.saopaulo",
            "sp_aws_lb.liberdade_alb01",
            "Remote State: alb_dns",
        ),
        # Tokyo remote_state.saopaulo -> SP peering attachment (Remote State: peering_id)
        (
            "tokyo_data.terraform_remote_state.saopaulo",
            "sp_aws_ec2_transit_gateway_peering_attachment.liberdade_to_shinjuku_peer01",
            "Remote State: peering_id",
        ),
        # Tokyo SG rule -> SP VPC (Cross-Region SG: 10.76.0.0/16)
        (
            "tokyo_aws_security_group_rule.shinjuku_rds_ingress_from_liberdade01",
            "sp_aws_vpc.liberdade_vpc01",
            "Cross-Region SG: 10.76.0.0/16",
        ),
        # Tokyo CloudFront -> SP ALB (CF Failover Origin)
        (
            "tokyo_aws_cloudfront_distribution.chewbacca_cf01",
            "sp_aws_lb.liberdade_alb01",
            "CF Failover Origin",
        ),
    ]

    lines.append('    // ---- Cross-Region Edges ----')
    for src, dst, label in cross_edges:
        # Verify both nodes exist in the graph (warn if not)
        src_exists = src in tokyo_nodes or src in sp_nodes
        dst_exists = dst in tokyo_nodes or dst in sp_nodes
        if not src_exists:
            print(f"  WARNING: cross-edge source not found: {src}")
        if not dst_exists:
            print(f"  WARNING: cross-edge target not found: {dst}")
        lines.append(
            f'    {quote(src)} -> {quote(dst)} '
            f'[label={quote(label)}, {cross_style}];'
        )
    lines.append('')
    lines.append('}')

    dot_text = "\n".join(lines) + "\n"

    # Write output DOT
    with open(OUT_DOT, "w") as fh:
        fh.write(dot_text)
    print(f"\nWrote combined DOT: {OUT_DOT}")
    print(f"  Size: {OUT_DOT.stat().st_size:,} bytes")

    # Count nodes and edges
    total_nodes = len(tokyo_nodes) + len(sp_nodes)
    total_intra_edges = len(tokyo_edges) + len(sp_edges)
    total_cross_edges = len(cross_edges)
    print(f"\n--- Graph Statistics ---")
    print(f"  Tokyo nodes:       {len(tokyo_nodes)}")
    print(f"  Sao Paulo nodes:   {len(sp_nodes)}")
    print(f"  Total nodes:       {total_nodes}")
    print(f"  Tokyo intra-edges: {len(tokyo_edges)}")
    print(f"  SP intra-edges:    {len(sp_edges)}")
    print(f"  Cross-region edges:{total_cross_edges}")
    print(f"  Total edges:       {total_intra_edges + total_cross_edges}")

    # Render to SVG if graphviz available
    if GRAPHVIZ.exists() and GRAPHVIZ.is_file():
        print(f"\nRendering SVG with {GRAPHVIZ} ...")
        result = subprocess.run(
            [str(GRAPHVIZ), "-Tsvg", "-o", str(OUT_SVG), str(OUT_DOT)],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            print(f"  Wrote SVG: {OUT_SVG}")
            print(f"  SVG size:  {OUT_SVG.stat().st_size:,} bytes")
        else:
            print(f"  ERROR rendering SVG: {result.stderr}", file=sys.stderr)
    else:
        print(f"\nGraphviz not found at {GRAPHVIZ} -- skipping SVG render.")

    print("\nDone.")


if __name__ == "__main__":
    main()
