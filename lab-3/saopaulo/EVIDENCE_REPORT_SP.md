# Lab 3 — Malgus Evidence Report (Sao Paulo / MacMini)

> **Generated**: 2026-02-08 ~11:15 UTC
> **Account**: `<ACCOUNT_ID>`
> **Region**: `sa-east-1` (Sao Paulo)
> **Domain**: `keepuneat.click`
> **Branch**: `nikrdf-armageddon-branch`
> **Machine**: MacMini (Phase 2)

---

## Executive Summary

| Script | Status | Verdict |
|--------|--------|---------|
| `malgus_residency_proof.py` | Ran | **PASS** — RDS exclusively in Tokyo, zero in SP |
| `malgus_tgw_corridor_proof.py` | Ran | **PASS** — Both TGWs available, peering active, all RT associated |
| `malgus_cloudtrail_last_changes.py` | Ran | **INFO** — Steady-state, read-only monitoring traffic |
| `malgus_waf_summary.py` | Ran | **INFO** — WAF logging just enabled, no log data yet |
| `malgus_cloudfront_log_explainer.py` | Skipped | **N/A** — CF standard logging not enabled (MacPro manages CF) |
| **Live SSM TCP Test** | Ran | **PASS** — SP EC2 -> Tokyo RDS port 3306 = CONNECTION_SUCCESS |

---

## 1. Data Residency Proof (`malgus_residency_proof.py`)

> *"Show me the database lives ONLY in Tokyo." -- Malgus*

### Result: PASS

**Assertion**: RDS instances exist in Tokyo AND zero RDS instances in Sao Paulo.

### Tokyo (ap-northeast-1)

| Field | Value |
|-------|-------|
| Instance ID | `chewbacca-rds01` |
| AZ | `ap-northeast-1c` |
| Endpoint | `chewbacca-rds01.c3mawwi62nru.ap-northeast-1.rds.amazonaws.com` |

### Sao Paulo (sa-east-1)

| Field | Value |
|-------|-------|
| RDS Instances | **0** (empty) |

### Why This Matters (APPI Compliance)
- Japan's Act on Protection of Personal Information (APPI) requires that medical data remains within controlled jurisdictions
- RDS is exclusively in Tokyo -- Sao Paulo reads via TGW, never stores locally
- This is auditable proof that data residency controls are working
- SP EC2 connects to Tokyo RDS cross-region via boto3 (Secrets Manager) and TGW (MySQL)

---

## 2. TGW Corridor Proof (`malgus_tgw_corridor_proof.py`)

> *"Corridors must be explicit. Malgus hates 'it should route' -- he wants 'it DOES route.'"*

### Result: PASS — Both TGWs available, peering bidirectional, all attachments associated

### Tokyo TGW — Shinjuku Hub

| Field | Value |
|-------|-------|
| TGW ID | `tgw-057b23da16e7b2e2c` |
| Name | `shinjuku-tgw01` |
| State | `available` |
| Description | `shinjuku-tgw01 (Tokyo hub)` |
| ASN | `64512` |
| Default RT Association | `disable` (explicit custom RT) |
| Default RT Propagation | `disable` (explicit static routes) |
| DNS Support | `enable` |

#### Tokyo Attachments (2)

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | peering | `tgw-082eb2bf890ba9980` (SP) | available | `tgw-rtb-0d5737a98b213a2b7` associated |
| `tgw-attach-0e955d258bcd19199` | vpc | `vpc-04a641831a1e6a4d5` (Tokyo) | available | `tgw-rtb-0d5737a98b213a2b7` associated |

### Sao Paulo TGW — Liberdade Spoke

| Field | Value |
|-------|-------|
| TGW ID | `tgw-082eb2bf890ba9980` |
| Name | `liberdade-tgw01` |
| State | `available` |
| Description | `liberdade-tgw01 (Sao Paulo spoke)` |
| ASN | `64512` |
| Default RT Association | `enable` (auto-associate) |
| Default RT Propagation | `enable` (auto-propagate) |
| DNS Support | `enable` |

#### Sao Paulo Attachments (2)

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | peering | `tgw-057b23da16e7b2e2c` (Tokyo) | available | `tgw-rtb-06e9da91b366a732d` associated |
| `tgw-attach-05073041a9a8fecc9` | vpc | `vpc-01adf59fe5cd62857` (SP) | available | `tgw-rtb-06e9da91b366a732d` associated |

### Corridor Topology
```
  Tokyo VPC (10.75.0.0/16)
       |
       v
  shinjuku-tgw01 <---- peering (tgw-attach-0d30f46b569c358d6) ----> liberdade-tgw01
  (tgw-057b23da...)                  available                      (tgw-082eb2bf...)
       |                                                                    |
       v                                                                    v
  Tokyo RT (tgw-rtb-0d5737a...)                                SP RT (tgw-rtb-06e9da...)
  - 10.76.0.0/16 -> peering                                    - 10.75.0.0/16 -> peering
       |                                                                    |
       v                                                                    v
  Tokyo VPC (10.75.0.0/16)                                     SP VPC (10.76.0.0/16)
```

### Key Findings
- Both peering attachments share the same ID (`tgw-attach-0d30f46b569c358d6`) -- confirms bidirectional link
- Both are **associated** to their respective route tables -- no blackhole risk
- Tokyo uses explicit RT (`disable` auto-association) -- intentional, prevents the `Resource.AlreadyAssociated` bug
- Sao Paulo uses auto-association -- simpler spoke config
- SP TGW has static route `10.75.0.0/16 -> peering` (created after Phase 3 acceptance)

### Live TCP Connectivity Proof (SSM)

| Field | Value |
|-------|-------|
| Source | SP EC2 `i-0a2a60715a2f2e4f6` (10.76.101.89) |
| Target | Tokyo RDS `chewbacca-rds01.c3mawwi62nru.ap-northeast-1.rds.amazonaws.com:3306` (10.75.128.162) |
| Result | **CONNECTION_SUCCESS** |
| Method | `aws ssm send-command` with `/dev/tcp` probe |

---

## 3. CloudTrail Last Changes (`malgus_cloudtrail_last_changes.py`)

> *"Who changed what, and when?" Malgus doesn't trust anyone. He demands an audit trail.*

### Result: Steady-State — Infrastructure stable, monitoring noise only

### Tokyo (ap-northeast-1) — 50 events / 2h window

| Event Pattern | Count | User | Notes |
|--------------|-------|------|-------|
| `DescribeAlarms` | ~40 | AWSCLI | CloudWatch alarm evaluation (normal polling) |
| `UpdateInstanceInformation` | 3 | `i-004df5c55d7f72892` | SSM agent heartbeat (Tokyo EC2) |
| `ListInstanceAssociations` | 2 | `i-004df5c55d7f72892` | SSM agent check-in |
| `DescribeMetricFilters` | 2 | AWSCLI | CW monitoring reads |
| `AssumeRole` | 1 | (service) | STS role assumption |

### Sao Paulo (sa-east-1) — 50 events / 2h window

| Event Pattern | Count | User | Notes |
|--------------|-------|------|-------|
| `DescribeAlarms` | ~42 | AWSCLI | CloudWatch alarm evaluation (normal polling) |
| `UpdateInstanceInformation` | 3 | `i-0a2a60715a2f2e4f6` | SSM agent heartbeat (SP EC2) |
| `ListInstanceAssociations` | 1 | `i-0a2a60715a2f2e4f6` | SSM agent check-in |
| `DescribeMetricFilters` | 2 | AWSCLI | CW monitoring reads |

### Interpretation
- **Both regions are quiet** -- no mutating events (Create/Delete/Update) in the 2h window
- All activity is read-only monitoring: CloudWatch alarm evaluations and SSM agent heartbeats
- **Tokyo EC2** = `i-004df5c55d7f72892`, **SP EC2** = `i-0a2a60715a2f2e4f6` -- both healthy (SSM heartbeats active)
- The WAF rule additions and TGW static route creation happened earlier and are outside this window
- Infrastructure is in steady-state post-deployment

---

## 4. WAF Summary (`malgus_waf_summary.py`)

> *"Show me the shields." -- Malgus*

### Result: WAF Logging Active, No Traffic Yet

**Log Group**: `aws-waf-logs-liberdade-sp-webacl` (sa-east-1)
**Time Window**: 120 minutes
**Retention**: 30 days

### Action Breakdown

| Action | Hits |
|--------|------|
| (none) | 0 |

### WAF Rules Deployed (7 total)

| Priority | Rule | Type |
|----------|------|------|
| 0 | `AWSManagedRulesAmazonIpReputationList` | Managed (override: none) |
| 1 | `AWSManagedRulesCommonRuleSet` | Managed (override: none) |
| 2 | `AWSManagedRulesKnownBadInputsRuleSet` | Managed (override: none) |
| 3 | `AWSManagedRulesSQLiRuleSet` | Managed (override: none) |
| 5 | `BlockWordPressProbes` | Custom (action: block) |
| 6 | `RateLimitPerIP` (300/5min) | Custom (action: block) |
| 7 | `AWSManagedRulesWordPressRuleSet` | Managed (override: none) |

### Why Zero Traffic
- WAF logging was just enabled in this session (the `aws_wafv2_web_acl_logging_configuration` resource)
- SP ALB is behind origin cloaking -- only CloudFront can reach it via `X-Chewbacca-Growl` header
- CloudFront currently routes primarily to Tokyo origin; SP is the failover
- Once traffic flows through the SP origin (failover test or direct probe), WAF logs will populate

### Comparison with Tokyo WAF
- Tokyo WAF detected WordPress scanners (28/31 requests probing `/wp-admin/`, `/wordpress/`)
- SP now has **custom Rule 5** (`BlockWordPressProbes`) that will block those same paths
- SP also has **Rule 6** (`RateLimitPerIP`) at 300 req/5min -- scanner IPs would be throttled
- Both regions now have 7 WAF rules (4 AWS managed + 3 custom/managed additions)

---

## 5. CloudFront Log Explainer (`malgus_cloudfront_log_explainer.py`)

> *"The Empire doesn't argue with feelings. It counts outcomes."*

### Result: NOT APPLICABLE (SP Context)

**Reason**: CloudFront is a global service managed from Tokyo's Terraform state (MacPro). The SP origin (`origin-saopaulo.keepuneat.click`) is configured as the failover target in CloudFront's origin group. Standard CloudFront logging analysis should be run from MacPro.

### SP Origin Configuration

| Field | Value |
|-------|-------|
| Origin FQDN | `origin-saopaulo.keepuneat.click` |
| ALB DNS | `liberdade-alb01-2008518368.sa-east-1.elb.amazonaws.com` |
| Protocol | `https-only` |
| ACM Cert | `*.keepuneat.click` (DNS validated in SP) |
| Role | Failover origin (activated on Tokyo 5xx) |

---

## Infrastructure Resource Map

| Resource | Region | ID / Value |
|----------|--------|------------|
| SP VPC | sa-east-1 | `vpc-01adf59fe5cd62857` (10.76.0.0/16) |
| SP EC2 | sa-east-1 | `i-0a2a60715a2f2e4f6` (10.76.101.89, t3.micro) |
| SP ALB | sa-east-1 | `liberdade-alb01` |
| SP WAF | sa-east-1 | `liberdade-sp-waf01` (7 rules) |
| SP TGW | sa-east-1 | `tgw-082eb2bf890ba9980` (Liberdade spoke) |
| TGW Peering | cross-region | `tgw-attach-0d30f46b569c358d6` (available) |
| Tokyo TGW | ap-northeast-1 | `tgw-057b23da16e7b2e2c` (Shinjuku hub) |
| Tokyo VPC | ap-northeast-1 | `vpc-04a641831a1e6a4d5` (10.75.0.0/16) |
| RDS | ap-northeast-1 | `chewbacca-rds01` (ap-northeast-1c) |
| RDS in SP | sa-east-1 | None (APPI compliant) |
| Origin DNS | sa-east-1 | `origin-saopaulo.keepuneat.click` -> SP ALB |
| SNS Topic | sa-east-1 | `liberdade-alb-incidents` (email confirmed) |
| ALB Logs | sa-east-1 | `s3://liberdade-alb-logs-<ACCOUNT_ID>` |
| WAF Logs | sa-east-1 | `aws-waf-logs-liberdade-sp-webacl` (30-day retention) |

### CloudWatch Alarms

| Alarm | Metric | Threshold | Status |
|-------|--------|-----------|--------|
| `liberdade-alb-5xx-high` | HTTPCode_Target_5XX_Count | >= 10 (2 periods) | Active |
| `liberdade-alb-unhealthy-hosts` | UnHealthyHostCount | >= 1 | Active |
| `liberdade-db-connection-failure` | DBConnectionErrors (custom) | >= 3 | Active |

### VPC Endpoints (6)

| Endpoint | Type | Purpose |
|----------|------|---------|
| S3 | Gateway | ALB logs, general S3 access |
| SSM | Interface | Session Manager (no SSH) |
| SSM Messages | Interface | SSM communication channel |
| EC2 Messages | Interface | SSM communication channel |
| CloudWatch Logs | Interface | Log shipping |
| CloudWatch Monitoring | Interface | Metric publishing |

---

## Scripts Reference

| Script | What It Proves | Regions | Args Needed |
|--------|---------------|---------|-------------|
| `malgus_residency_proof.py` | RDS only in Tokyo (APPI) | Both | None |
| `malgus_tgw_corridor_proof.py` | TGW peering is active + associated | Both | None |
| `malgus_cloudtrail_last_changes.py` | Recent infra changes (audit trail) | Both | None (2h default) |
| `malgus_waf_summary.py` | WAF actions, top IPs, blocked rules | Per log group | `--log-group`, `--region` |
| `malgus_cloudfront_log_explainer.py` | Cache Hit/Miss rates | S3 bucket | `--bucket`, `--prefix` |

### Running All Scripts (SP)
```bash
cd lab-3/saopaulo/python/

# Data residency proof (both regions)
python3 malgus_residency_proof.py

# TGW corridor proof (both regions)
python3 malgus_tgw_corridor_proof.py

# CloudTrail audit (both regions, 2h window)
python3 malgus_cloudtrail_last_changes.py

# SP WAF summary (requires traffic to have hit the ALB)
python3 malgus_waf_summary.py \
  --log-group aws-waf-logs-liberdade-sp-webacl \
  --region sa-east-1 \
  --minutes 120

# CloudFront logs (run from MacPro — CF is managed there)
# python3 malgus_cloudfront_log_explainer.py --bucket <BUCKET> --prefix cloudfront-logs/
```

---

*Generated by Claude Code on MacMini (Sao Paulo state) -- 2026-02-08*
