# Lab 3 — Multi-Region Infrastructure Evidence Report

> **Date**: 2026-02-08
> **Account**: `<ACCOUNT_ID>`
> **Domain**: `keepuneat.click`
> **Branch**: `nikrdf-armageddon-branch`
> **Primary Region**: `ap-northeast-1` (Tokyo) — APPI data authority
> **Failover Region**: `sa-east-1` (Sao Paulo) — stateless compute only

---

## Architecture Overview

```
                        Browser
                          |
                        HTTPS
                          |
                   CloudFront (us-east-1)
                   + Edge WAF (7 rules)
                   + Origin Group (failover)
                  /                        \
         primary /                          \ failover (on 5xx)
                /                            \
  origin-tokyo.keepuneat.click     origin-saopaulo.keepuneat.click
     Tokyo ALB (https-only)            SP ALB (https-only)
     + Regional WAF (7 rules)          + Regional WAF (7 rules)
            |                                |
       Tokyo EC2                          SP EC2
            |                                |
       Tokyo RDS  <----  TGW Peering  ------>|
    (chewbacca-rds01)    (cross-region)      |
     ap-northeast-1c                    reads via TGW
            |                           (never stores)
     Data Authority
     (APPI Compliant)
```

**Design rationale**: Tokyo is the single data authority. Sao Paulo is stateless failover compute — it reads credentials from Tokyo Secrets Manager via IAM/boto3 and queries Tokyo RDS over the TGW peering corridor. No patient data is stored outside `ap-northeast-1`.

---

## Executive Summary

| # | Verification | Source | Result |
|---|-------------|--------|--------|
| 1 | Data Residency (APPI) | `malgus_residency_proof.py` | **PASS** — RDS exclusively in Tokyo, zero in SP |
| 2 | TGW Corridor | `malgus_tgw_corridor_proof.py` | **PASS** — Bidirectional peering active, all RT associated |
| 3 | Live Connectivity | SSM TCP probe (SP to Tokyo) | **PASS** — Port 3306 CONNECTION_SUCCESS |
| 4 | CloudTrail Audit | `malgus_cloudtrail_last_changes.py` | **INFO** — Steady-state, no unauthorized mutations |
| 5 | WAF — Tokyo | `malgus_waf_summary.py` | **ALERT** — WordPress scanners detected, rules deployed |
| 6 | WAF — Sao Paulo | `malgus_waf_summary.py` | **INFO** — Rules active, no traffic yet (failover origin) |
| 7 | CloudFront Logs | `malgus_cloudfront_log_explainer.py` | **N/A** — Standard logging not enabled |

---

## 1. Data Residency Proof

**Objective**: Confirm that all RDS database instances reside exclusively in Tokyo, satisfying APPI data residency requirements.

### Tokyo (ap-northeast-1)

| Field | Value |
|-------|-------|
| Instance ID | `chewbacca-rds01` |
| Availability Zone | `ap-northeast-1c` |
| Endpoint | `chewbacca-rds01.c3mawwi62nru.ap-northeast-1.rds.amazonaws.com` |
| Engine | MySQL |
| Secret | `chewbacca/rds/mysql` (Secrets Manager, ap-northeast-1) |

### Sao Paulo (sa-east-1)

| Field | Value |
|-------|-------|
| RDS Instances | **0** |

### APPI Compliance Summary

Japan's Act on Protection of Personal Information (APPI) requires that medical data remains within controlled jurisdictions. This verification confirms:

- RDS is exclusively in Tokyo — Sao Paulo never stores data locally
- SP EC2 retrieves database credentials cross-region from Tokyo Secrets Manager via IAM role + boto3
- SP EC2 connects to Tokyo RDS over the TGW peering corridor (MySQL/3306)
- The credential retrieval and data path are both encrypted in transit (TLS + TGW encryption)

---

## 2. TGW Corridor Proof

**Objective**: Verify that the Transit Gateway peering between Tokyo and Sao Paulo is active, bidirectional, and correctly associated to route tables.

### Tokyo TGW — Shinjuku Hub

| Field | Value |
|-------|-------|
| TGW ID | `tgw-057b23da16e7b2e2c` |
| Name | `shinjuku-tgw01` |
| State | `available` |
| ASN | `64512` |
| Default RT Association | `disable` (explicit custom RT) |
| Default RT Propagation | `disable` (explicit static routes) |
| DNS Support | `enable` |

**Attachments**:

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | peering | `tgw-082eb2bf890ba9980` (SP) | available | `tgw-rtb-0d5737a98b213a2b7` — associated |
| `tgw-attach-0e955d258bcd19199` | vpc | `vpc-04a641831a1e6a4d5` (Tokyo) | available | `tgw-rtb-0d5737a98b213a2b7` — associated |

### Sao Paulo TGW — Liberdade Spoke

| Field | Value |
|-------|-------|
| TGW ID | `tgw-082eb2bf890ba9980` |
| Name | `liberdade-tgw01` |
| State | `available` |
| ASN | `64512` |
| Default RT Association | `enable` (auto-associate) |
| Default RT Propagation | `enable` (auto-propagate) |
| DNS Support | `enable` |

**Attachments**:

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | peering | `tgw-057b23da16e7b2e2c` (Tokyo) | available | `tgw-rtb-06e9da91b366a732d` — associated |
| `tgw-attach-05073041a9a8fecc9` | vpc | `vpc-01adf59fe5cd62857` (SP) | available | `tgw-rtb-06e9da91b366a732d` — associated |

### Corridor Topology

```
Tokyo VPC (10.75.0.0/16)                              SP VPC (10.76.0.0/16)
       |                                                      |
       v                                                      v
  shinjuku-tgw01  <--- peering (tgw-attach-0d30f46b...) --->  liberdade-tgw01
       |                        [available]                        |
       v                                                      v
  Tokyo RT (tgw-rtb-0d5737a...)                    SP RT (tgw-rtb-06e9da...)
  route: 10.76.0.0/16 -> peering                  route: 10.75.0.0/16 -> peering
```

### Key Findings

- Both peering attachments share the same ID (`tgw-attach-0d30f46b569c358d6`) — confirms the link is bidirectional
- All attachments are associated to their respective route tables — no blackhole risk
- Tokyo uses explicit RT association (`disable` auto) — intentional design to prevent the `Resource.AlreadyAssociated` error encountered during Phase 3
- Sao Paulo uses auto-association — simpler spoke configuration
- SP static route `10.75.0.0/16 -> peering` was created after Phase 3 peering acceptance

---

## 3. Live Connectivity Proof

**Objective**: Confirm that SP EC2 can reach Tokyo RDS over the TGW corridor at the application layer (MySQL/3306).

| Field | Value |
|-------|-------|
| Source | SP EC2 `i-0a2a60715a2f2e4f6` (10.76.101.89) |
| Target | Tokyo RDS `chewbacca-rds01.c3mawwi62nru.ap-northeast-1.rds.amazonaws.com:3306` (10.75.128.162) |
| Method | `aws ssm send-command` with `/dev/tcp` probe |
| Result | **CONNECTION_SUCCESS** |

This test was executed via SSM (no SSH required). The SP EC2 instance successfully opened a TCP connection to the Tokyo RDS endpoint on port 3306 through the TGW peering corridor, confirming end-to-end network path availability.

---

## 4. CloudTrail Audit

**Objective**: Verify infrastructure stability and detect any unauthorized or unexpected mutations.

### Tokyo (ap-northeast-1) — 48-hour window

| Time (UTC) | Service | Action | User | Notes |
|------------|---------|--------|------|-------|
| 2026-02-08 02:51 | ec2 | `RevokeSecurityGroupIngress` | AWSCLI | SG cleanup (Phase 3 reconciliation) |
| 2026-02-08 02:16 | ec2 | `AssociateTransitGatewayRouteTable` | AWSCLI | TGW peering RT import |

Plus ~48 read-only events (CloudWatch alarm evaluations, SSM agent heartbeats).

### Sao Paulo (sa-east-1) — 48-hour window

| Time (UTC) | Service | Action | User | Notes |
|------------|---------|--------|------|-------|
| 2026-02-08 01:54 | ec2 | `CreateTransitGatewayRoute` | AWSCLI | Static route to Tokyo CIDR |
| 2026-02-08 01:39-01:52 | monitoring | `SetAlarmState` x9 | AWSCLI | Alarm validation tests |
| 2026-02-08 01:09-01:18 | monitoring | `PutMetricAlarm` x3 | AWSCLI | Alarm creation |
| 2026-02-08 01:09 | sns | `CreateTopic`, `Subscribe` | AWSCLI | Incident notification setup |

### Interpretation

- **Tokyo is quiet** — only two mutating events, both expected Phase 3 cleanup
- **Sao Paulo** shows the Phase 2 deployment sequence: SNS topic, CloudWatch alarms, alarm tests, then the Phase 3 TGW static route
- All actions originated from `AWSCLI` user — consistent with Terraform apply and manual CLI operations
- No unauthorized access patterns detected
- Infrastructure was in steady-state at time of report generation

---

## 5. WAF Analysis

### Tokyo WAF (`aws-waf-logs-chewbacca-tokyo-webacl`)

**Time Window**: 120 minutes | **Region**: ap-northeast-1

**Action Breakdown**:

| Action | Count |
|--------|-------|
| ALLOW | 31 |
| BLOCK | 0 |

**Top URIs**:

| URI | Hits | Assessment |
|-----|------|------------|
| `/wordpress/wp-admin/setup-config.php` | 14 | WordPress scanner |
| `/wp-admin/setup-config.php` | 14 | WordPress scanner |
| `/` | 3 | Legitimate |

**Top Source Countries**:

| Country | Hits |
|---------|------|
| Sweden | 23 |
| Germany | 5 |
| France | 2 |
| United States | 1 |

**Finding**: 28 of 31 requests (90%) were WordPress enumeration probes. This is a Flask application, not WordPress — all probes returned 404. These scanners triggered the deployment of custom WAF rules (see below).

### Sao Paulo WAF (`aws-waf-logs-liberdade-sp-webacl`)

**Time Window**: 120 minutes | **Region**: sa-east-1

| Action | Count |
|--------|-------|
| (none) | 0 |

**Why zero traffic**: SP is the failover origin. CloudFront routes to Tokyo by default. SP WAF will see traffic only during a failover event (Tokyo 5xx) or directed probe testing.

### WAF Rules Deployed (Both Regions — 7 rules each)

| Priority | Rule | Type | Action |
|----------|------|------|--------|
| 0 | `AWSManagedRulesAmazonIpReputationList` | AWS Managed | Block |
| 1 | `AWSManagedRulesCommonRuleSet` | AWS Managed | Block |
| 2 | `AWSManagedRulesKnownBadInputsRuleSet` | AWS Managed | Block |
| 3 | `AWSManagedRulesSQLiRuleSet` | AWS Managed | Block |
| 5 | `BlockWordPressProbes` | Custom | Block (`/wp-admin/*`, `/wordpress/*`) |
| 6 | `RateLimitPerIP` (300 req/5min) | Custom | Block |
| 7 | `AWSManagedRulesWordPressRuleSet` | AWS Managed | Block |

**CloudFront Edge WAF** (`us-east-1`): Same 7-rule configuration applied at the edge distribution, providing defense-in-depth before traffic reaches either regional ALB.

### Remediation Timeline

The WordPress scanner detection in the initial Tokyo WAF report led to the following hardening actions in the same session:

1. Added custom `BlockWordPressProbes` rule (URI path match: `/wp-admin/*`, `/wordpress/*`)
2. Added `RateLimitPerIP` rule (300 requests per 5 minutes per IP)
3. Added `AWSManagedRulesWordPressRuleSet` managed rule group
4. Deployed identical rule set to SP WAF and CloudFront edge WAF
5. Enabled WAF logging in all three locations (Tokyo, SP, CloudFront)

---

## 6. CloudFront Configuration

CloudFront distribution `E2GBKEHK0L045Y` is configured with an origin group for automatic failover:

| Setting | Value |
|---------|-------|
| Distribution ID | `E2GBKEHK0L045Y` |
| Primary Origin | `origin-tokyo.keepuneat.click` (https-only) |
| Failover Origin | `origin-saopaulo.keepuneat.click` (https-only) |
| Failover Trigger | 5xx from primary |
| Origin Protocol | `https-only` (both origins) |
| Origin Cloaking | `X-Chewbacca-Growl` custom header (random_password, 32 chars) |
| Edge WAF | 7 rules (same as regional WAFs) |
| App URL | `https://app.keepuneat.click` |

**Origin cloaking**: Both ALBs validate the `X-Chewbacca-Growl` header on every request. Direct ALB access without the header returns 403. This ensures all traffic flows through CloudFront and its edge WAF, preventing origin bypass attacks.

**Why https-only**: APPI compliance requires encryption in transit for medical data. The origin secret header and all application data are encrypted end-to-end. Each regional ALB has a wildcard ACM certificate (`*.keepuneat.click`) enabling TLS termination on the custom origin FQDN.

---

## Infrastructure Resource Map

### Global

| Resource | Region | Identifier |
|----------|--------|------------|
| CloudFront | us-east-1 (edge) | `E2GBKEHK0L045Y` |
| CloudFront WAF | us-east-1 | `chewbacca-cf-webacl` (7 rules) |
| App URL | — | `https://app.keepuneat.click` |

### Tokyo (ap-northeast-1) — Primary

| Resource | Identifier |
|----------|------------|
| VPC | `vpc-04a641831a1e6a4d5` (10.75.0.0/16) |
| EC2 | `i-004df5c55d7f72892` (t3.micro) |
| RDS | `chewbacca-rds01` (ap-northeast-1c, MySQL) |
| ALB | `chewbacca-alb01` |
| WAF | `chewbacca-tokyo-webacl` (7 rules) |
| TGW | `tgw-057b23da16e7b2e2c` (shinjuku-tgw01) |
| Secrets Manager | `chewbacca/rds/mysql` |
| Origin DNS | `origin-tokyo.keepuneat.click` |
| WAF Logs | `aws-waf-logs-chewbacca-tokyo-webacl` |

### Sao Paulo (sa-east-1) — Failover

| Resource | Identifier |
|----------|------------|
| VPC | `vpc-01adf59fe5cd62857` (10.76.0.0/16) |
| EC2 | `i-0a2a60715a2f2e4f6` (10.76.101.89, t3.micro) |
| RDS | None (APPI compliant — stateless compute only) |
| ALB | `liberdade-alb01` |
| WAF | `liberdade-sp-waf01` (7 rules) |
| TGW | `tgw-082eb2bf890ba9980` (liberdade-tgw01) |
| Origin DNS | `origin-saopaulo.keepuneat.click` |
| SNS Topic | `liberdade-alb-incidents` |
| WAF Logs | `aws-waf-logs-liberdade-sp-webacl` (30-day retention) |
| ALB Logs | `s3://liberdade-alb-logs-<ACCOUNT_ID>` |

### Cross-Region

| Resource | Identifier |
|----------|------------|
| TGW Peering | `tgw-attach-0d30f46b569c358d6` (bidirectional) |
| Tokyo CIDR | 10.75.0.0/16 |
| SP CIDR | 10.76.0.0/16 |

### CloudWatch Alarms (Sao Paulo)

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| `liberdade-alb-5xx-high` | HTTPCode_Target_5XX_Count | >= 10 (2 periods) |
| `liberdade-alb-unhealthy-hosts` | UnHealthyHostCount | >= 1 |
| `liberdade-db-connection-failure` | DBConnectionErrors (custom) | >= 3 |

### VPC Endpoints (Sao Paulo — SSM-only access, no SSH)

| Endpoint | Type | Purpose |
|----------|------|---------|
| S3 | Gateway | ALB logs, general S3 access |
| SSM | Interface | Session Manager |
| SSM Messages | Interface | SSM communication channel |
| EC2 Messages | Interface | SSM communication channel |
| CloudWatch Logs | Interface | Log shipping |
| CloudWatch Monitoring | Interface | Metric publishing |

---

## Verification Scripts

| Script | Purpose | Regions Queried | Arguments |
|--------|---------|-----------------|-----------|
| `malgus_residency_proof.py` | Prove RDS exists only in Tokyo (APPI) | Both | None |
| `malgus_tgw_corridor_proof.py` | Prove TGW peering is active and associated | Both | None |
| `malgus_cloudtrail_last_changes.py` | Audit recent infrastructure mutations | Both | None (2h default) |
| `malgus_waf_summary.py` | Analyze WAF actions, top IPs, blocked rules | Per log group | `--log-group`, `--region` |
| `malgus_cloudfront_log_explainer.py` | Analyze cache hit/miss rates | S3 bucket | `--bucket`, `--prefix` |

### Reproducing This Report

```bash
cd lab-3/python/

# 1. Data residency proof
python3 malgus_residency_proof.py

# 2. TGW corridor proof
python3 malgus_tgw_corridor_proof.py

# 3. CloudTrail audit (both regions, default 2h window)
python3 malgus_cloudtrail_last_changes.py

# 4. Tokyo WAF summary
python3 malgus_waf_summary.py \
  --log-group aws-waf-logs-chewbacca-tokyo-webacl \
  --region ap-northeast-1 \
  --minutes 120

# 5. Sao Paulo WAF summary
python3 malgus_waf_summary.py \
  --log-group aws-waf-logs-liberdade-sp-webacl \
  --region sa-east-1 \
  --minutes 120

# 6. CloudFront logs (requires standard logging to be enabled)
# python3 malgus_cloudfront_log_explainer.py --bucket <BUCKET> --prefix cloudfront-logs/
```

---

## Split-State Terraform Model

This lab uses a split-state architecture across two machines:

| State | Machine | Region | S3 Key | Lock Table |
|-------|---------|--------|--------|------------|
| Tokyo | MacPro | ap-northeast-1 | `lab3/tokyo/terraform.tfstate` | `lab3-tokyo-tf-locks` |
| Sao Paulo | MacMini | sa-east-1 | `lab3/saopaulo/terraform.tfstate` | `lab3-saopaulo-tf-locks` |

**Backend**: `s3://class7-armagaggeon-tf-bucket` (us-east-1)

Sao Paulo reads Tokyo outputs via `terraform_remote_state` data source for cross-region references (TGW ID, origin secret header, RDS endpoint).

---

## Deployment Phases

| Phase | Description | Machine | Key Resources |
|-------|-------------|---------|---------------|
| 1 | Tokyo core: VPC, EC2, RDS, ALB, WAF, TGW, CloudFront | MacPro | Full primary stack |
| 2 | Sao Paulo core: VPC, EC2, ALB, WAF, TGW, VPC endpoints | MacMini | Stateless failover |
| 3 | Cross-region integration: TGW peering acceptance, origin group failover, static routes | Both | Peering + failover |

---

*Report generated 2026-02-08 — Lab 3 Multi-Region Split-State Infrastructure*
