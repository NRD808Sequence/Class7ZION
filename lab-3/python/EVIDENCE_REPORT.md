# 🛡️ Lab 3 — Malgus Evidence Report

> **Generated**: 2026-02-08 ~10:30 UTC
> **Account**: `<ACCOUNT_ID>`
> **Domain**: `keepuneat.click`
> **Branch**: `nikrdf-armageddon-branch`

---

## 📋 Executive Summary

| Script | Status | Verdict |
|--------|--------|---------|
| `malgus_residency_proof.py` | ✅ Ran | **PASS** — RDS exclusively in Tokyo |
| `malgus_tgw_corridor_proof.py` | ✅ Ran | **PASS** — Both TGWs available, peering active |
| `malgus_cloudtrail_last_changes.py` | ✅ Ran | **INFO** — Steady-state, minimal mutations in 48h |
| `malgus_waf_summary.py` | ✅ Ran | ⚠️ **ALERT** — WordPress scanner detected, 0 blocks |
| `malgus_cloudfront_log_explainer.py` | ⛔ Skipped | **N/A** — CF standard logging not enabled |

---

## 1️⃣ Data Residency Proof (`malgus_residency_proof.py`)

> *"Show me the database lives ONLY in Tokyo." — Malgus*

### Result: ✅ PASS

**Assertion**: RDS instances exist in Tokyo AND zero RDS instances in São Paulo.

### 🗼 Tokyo (ap-northeast-1)

| Field | Value |
|-------|-------|
| Instance ID | `chewbacca-rds01` |
| AZ | `ap-northeast-1c` |
| Endpoint | `chewbacca-rds01.c3mawwi62nru.ap-northeast-1.rds.amazonaws.com` |

### 🇧🇷 São Paulo (sa-east-1)

| Field | Value |
|-------|-------|
| RDS Instances | **0** (empty) |

### 💡 Why This Matters (APPI Compliance)
- Japan's Act on Protection of Personal Information (APPI) requires that medical data remains within controlled jurisdictions
- RDS is exclusively in Tokyo — São Paulo reads via TGW, never stores locally
- This is auditable proof that data residency controls are working

---

## 2️⃣ TGW Corridor Proof (`malgus_tgw_corridor_proof.py`)

> *"Corridors must be explicit. Malgus hates 'it should route' — he wants 'it DOES route.'"*

### Result: ✅ PASS — Both TGWs available, peering bidirectional

### 🗼 Tokyo TGW — Shinjuku Hub

| Field | Value |
|-------|-------|
| TGW ID | `tgw-057b23da16e7b2e2c` |
| Name | `shinjuku-tgw01` |
| State | ✅ `available` |
| Description | `shinjuku-tgw01 (Tokyo hub)` |
| ASN | `64512` |
| Default RT Association | `disable` (explicit custom RT) |
| Default RT Propagation | `disable` (explicit static routes) |
| DNS Support | `enable` |

#### Tokyo Attachments (2)

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | 🔗 **peering** | `tgw-082eb2bf890ba9980` (SP) | ✅ available | `tgw-rtb-0d5737a98b213a2b7` ✅ associated |
| `tgw-attach-0e955d258bcd19199` | 🖧 **vpc** | `vpc-04a641831a1e6a4d5` (Tokyo) | ✅ available | `tgw-rtb-0d5737a98b213a2b7` ✅ associated |

### 🇧🇷 São Paulo TGW — Liberdade Spoke

| Field | Value |
|-------|-------|
| TGW ID | `tgw-082eb2bf890ba9980` |
| Name | `liberdade-tgw01` |
| State | ✅ `available` |
| Description | `liberdade-tgw01 (Sao Paulo spoke)` |
| ASN | `64512` |
| Default RT Association | `enable` (auto-associate) |
| Default RT Propagation | `enable` (auto-propagate) |
| DNS Support | `enable` |

#### São Paulo Attachments (2)

| Attachment | Type | Resource | State | Route Table |
|-----------|------|----------|-------|-------------|
| `tgw-attach-0d30f46b569c358d6` | 🔗 **peering** | `tgw-057b23da16e7b2e2c` (Tokyo) | ✅ available | `tgw-rtb-06e9da91b366a732d` ✅ associated |
| `tgw-attach-05073041a9a8fecc9` | 🖧 **vpc** | `vpc-01adf59fe5cd62857` (SP) | ✅ available | `tgw-rtb-06e9da91b366a732d` ✅ associated |

### 💡 Corridor Topology
```
  Tokyo VPC (10.75.0.0/16)
       │
       ▼
  shinjuku-tgw01 ◄──── peering (tgw-attach-0d30f46b569c358d6) ────► liberdade-tgw01
  (tgw-057b23da...)                  ✅ available                    (tgw-082eb2bf...)
       │                                                                    │
       ▼                                                                    ▼
  Tokyo RT (tgw-rtb-0d5737a...)                                SP RT (tgw-rtb-06e9da...)
  - 10.76.0.0/16 → peering                                    - 10.75.0.0/16 → peering
       │                                                                    │
       ▼                                                                    ▼
  Tokyo VPC (10.75.0.0/16)                                     SP VPC (10.76.0.0/16)
```

### ✅ Key Findings
- Both peering attachments share the same ID (`tgw-attach-0d30f46b569c358d6`) — confirms bidirectional link
- Both are **associated** to their respective route tables — no blackhole risk
- Tokyo uses explicit RT (`disable` auto-association) — intentional, prevents the `Resource.AlreadyAssociated` bug
- São Paulo uses auto-association — simpler spoke config

---

## 3️⃣ CloudTrail Last Changes (`malgus_cloudtrail_last_changes.py`)

> *"Who changed what, and when?" Malgus doesn't trust anyone. He demands an audit trail.*

### Result: ℹ️ Steady-State — Infrastructure stable, minimal mutations

### 🗼 Tokyo (ap-northeast-1) — 2 mutating events / 48h

| Time (UTC-7) | Service | Action | User | Resource |
|-------------|---------|--------|------|----------|
| 2026-02-08 02:51:19 | `ec2` | `RevokeSecurityGroupIngress` | AWSCLI | `sg-03b6fb54a9fc3fc59` |
| 2026-02-08 02:16:47 | `ec2` | `AssociateTransitGatewayRouteTable` | AWSCLI | *(TGW peering RT import)* |

### 🇧🇷 São Paulo (sa-east-1) — 20 mutating events / 48h

| Time (UTC-7) | Service | Action | User | Resource |
|-------------|---------|--------|------|----------|
| 2026-02-08 01:54:39 | `ec2` | `CreateTransitGatewayRoute` | AWSCLI | *(static route to Tokyo)* |
| 2026-02-08 01:39:42–52 | `monitoring` | `SetAlarmState` ×9 | AWSCLI | `liberdade-db-connection-failure`, `liberdade-alb-unhealthy-hosts`, `liberdade-alb-5xx-high` |
| 2026-02-08 01:18:02–06 | `monitoring` | `SetAlarmState` ×2 | AWSCLI | `liberdade-alb-unhealthy-hosts` |
| 2026-02-08 01:14:31 | `monitoring` | `SetAlarmState` | AWSCLI | `liberdade-alb-unhealthy-hosts` |
| 2026-02-08 01:09:52 | `monitoring` | `PutMetricAlarm` ×3 | AWSCLI | `liberdade-db-connection-failure`, `liberdade-alb-5xx-high`, `liberdade-alb-unhealthy-hosts` |
| 2026-02-08 01:09:49–51 | `sns` | `CreateTopic`, `SetTopicAttributes` ×5, `Subscribe` | AWSCLI | `liberdade-alb-incidents` |

### 💡 Interpretation
- **Tokyo** is quiet — the SG revoke and TGW RT association were final Phase 3 reconciliation steps
- **São Paulo** shows the MacMini's alarm setup sequence: SNS topic creation → alarm creation → manual alarm tests (`SetAlarmState`)
- All actions from `AWSCLI` user — consistent with Terraform and manual CLI operations
- ⚠️ **Note**: Terraform `Create*` events (EC2, RDS, ALB, WAF) from initial deploy are >48h old and beyond the CloudTrail `lookup_events` pagination window. Use CloudTrail Lake or S3 event history for full deploy audit.

---

## 4️⃣ WAF Summary (`malgus_waf_summary.py`)

> *"Show me the shields." — Malgus*

### Result: ⚠️ WordPress Scanner Detected, Zero Blocks

**Log Group**: `aws-waf-logs-chewbacca-tokyo-webacl` (ap-northeast-1)
**Time Window**: 120 minutes

### 🎯 Action Breakdown

| Action | Hits |
|--------|------|
| ✅ ALLOW | 31 |
| 🚫 BLOCK | 0 |
| 📊 COUNT | 0 |

### 🌍 Top Countries

| Country | Hits | Flag |
|---------|------|------|
| Sweden | 23 | 🇸🇪 |
| Germany | 5 | 🇩🇪 |
| France | 2 | 🇫🇷 |
| United States | 1 | 🇺🇸 |

### 🔗 Top URIs

| URI | Hits | Assessment |
|-----|------|------------|
| `/wordpress/wp-admin/setup-config.php` | 14 | 🔴 **WordPress scanner** |
| `/wp-admin/setup-config.php` | 14 | 🔴 **WordPress scanner** |
| `/` | 3 | ✅ Normal |

### 📡 Top Client IPs

| IP | Hits | Notes |
|----|------|-------|
| `15.158.30.19` | 13 | Swedish range — scanner |
| `15.158.30.36` | 10 | Swedish range — scanner |
| `3.172.112.74` | 3 | |
| `3.172.112.68` | 2 | |
| `3.172.123.239` | 1 | |
| `3.172.123.230` | 1 | |
| `15.158.43.104` | 1 | |

### 🚫 Blocked by Rule

| Rule | Hits |
|------|------|
| *(none)* | 0 |

### ⚠️ Findings & Recommendations

1. **WordPress scanner active** — 28 of 31 requests (90%) are probing for WordPress admin pages (`/wp-admin/setup-config.php`). This is a Flask app, not WordPress, so the scans return 404s.

2. **Zero blocks is a concern** — The WAF is allowing everything through. Consider:
   - ✏️ Add a **URI-based rule** to block `/wp-admin/*` and `/wordpress/*` paths
   - ✏️ Enable **AWS Managed Rules** (e.g., `AWSManagedRulesCommonRuleSet`) which would catch WordPress enumeration
   - ✏️ Add a **rate-based rule** (e.g., >100 requests/5min from same IP = BLOCK)

3. **Geographic concentration** — 74% of traffic from Sweden (🇸🇪). If this is unexpected, consider a geo-match rule.

---

## 5️⃣ CloudFront Log Explainer (`malgus_cloudfront_log_explainer.py`)

> *"The Empire doesn't argue with feelings. It counts outcomes."*

### Result: ⛔ NOT APPLICABLE

**Reason**: CloudFront standard logging (S3) is not enabled on distribution `E2GBKEHK0L045Y`. The distribution uses WAF logging (via CloudWatch Logs) but does not ship standard access logs to S3.

### 💡 To Enable (Optional)
Add a `logging_config` block to `34-cloudfront.tf`:
```hcl
logging_config {
  include_cookies = false
  bucket          = aws_s3_bucket.cf_logs.bucket_domain_name
  prefix          = "cloudfront-logs/"
}
```

---

## 🏗️ Infrastructure Resource Map

| Resource | Region | ID / Value |
|----------|--------|------------|
| CloudFront | us-east-1 (edge) | `E2GBKEHK0L045Y` |
| TGW Tokyo | ap-northeast-1 | `tgw-057b23da16e7b2e2c` |
| TGW São Paulo | sa-east-1 | `tgw-082eb2bf890ba9980` |
| TGW Peering | cross-region | `tgw-attach-0d30f46b569c358d6` |
| Tokyo VPC | ap-northeast-1 | `vpc-04a641831a1e6a4d5` (10.75.0.0/16) |
| SP VPC | sa-east-1 | `vpc-01adf59fe5cd62857` (10.76.0.0/16) |
| RDS | ap-northeast-1 | `chewbacca-rds01` (ap-northeast-1c) |
| RDS in SP | sa-east-1 | ❌ None (APPI compliant) |
| App URL | — | `https://app.keepuneat.click` |
| Origin Tokyo | — | `origin-tokyo.keepuneat.click` |
| Origin SP | — | `origin-saopaulo.keepuneat.click` |
| Origin Protocol | — | `https-only` (both) |

---

## 🔑 Scripts Reference

| Script | What It Proves | Regions | Args Needed |
|--------|---------------|---------|-------------|
| `malgus_residency_proof.py` | RDS only in Tokyo (APPI) | Both | None |
| `malgus_tgw_corridor_proof.py` | TGW peering is active + associated | Both | None |
| `malgus_cloudtrail_last_changes.py` | Recent infra changes (audit trail) | Both | None (2h default) |
| `malgus_waf_summary.py` | WAF actions, top IPs, blocked rules | Per log group | `--log-group`, `--region` |
| `malgus_cloudfront_log_explainer.py` | Cache Hit/Miss rates | S3 bucket | `--bucket`, `--prefix` |

### Running All Scripts
```bash
# From lab-3/python/
python3 malgus_residency_proof.py
python3 malgus_tgw_corridor_proof.py
python3 malgus_cloudtrail_last_changes.py

# Tokyo WAF (requires --region since log group is in ap-northeast-1)
python3 malgus_waf_summary.py \
  --log-group aws-waf-logs-chewbacca-tokyo-webacl \
  --region ap-northeast-1 \
  --minutes 120

# São Paulo WAF (run from MacMini or with SP log group name)
# python3 malgus_waf_summary.py \
#   --log-group aws-waf-logs-liberdade-sp-webacl \
#   --region sa-east-1 \
#   --minutes 120

# CloudFront logs (requires standard logging enabled)
# python3 malgus_cloudfront_log_explainer.py --bucket <BUCKET> --prefix cloudfront-logs/
```

---

*🤖 Generated by Claude Code on MacPro (Tokyo state) — 2026-02-08*
