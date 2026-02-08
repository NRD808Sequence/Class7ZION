# Lab 3: Split-State Multi-Region Deploy Runbook

## Architecture

```
Browser --[HTTPS]--> CloudFront (us-east-1, WAF edge)
                         |
                         +-- Origin Group "multi-region-failover" (Phase 3)
                         |       |
                         |       +-- origin-tokyo.keepuneat.click (primary, https-only)
                         |       |       --> ALB --> EC2 --> RDS (APPI data)
                         |       |
                         |       +-- origin-saopaulo.keepuneat.click (failover, https-only)
                         |               --> ALB --> EC2 --> [reads Tokyo RDS via TGW]
                         |
                         +-- TGW Peering: Shinjuku (Tokyo) <--> Liberdade (Sao Paulo)
```

### Origin Cloaking (https-only)

CloudFront connects to ALBs via Route53 aliases (`origin-tokyo.keepuneat.click`,
`origin-saopaulo.keepuneat.click`) instead of raw ALB DNS names. This allows
`https-only` origin protocol because the wildcard ACM cert (`*.keepuneat.click`)
on each ALB matches the origin FQDN. The `X-Chewbacca-Growl` secret header and
all medical data are encrypted in transit.

**Why not http-only?** APPI compliance requires encryption in transit for medical
data. The origin secret header would be transmitted in plaintext otherwise.

## Prerequisites (Run Once)

```bash
# Create DynamoDB lock tables (from either Mac)
aws dynamodb create-table --table-name lab3-tokyo-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

aws dynamodb create-table --table-name lab3-saopaulo-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# Verify Route53 hosted zone exists
aws route53 list-hosted-zones --query "HostedZones[?Name=='keepuneat.click.'].Id"
```

---

## Phase 1: Tokyo Apply (MacPro)

**Who**: MacPro
**Dir**: `lab-3/tokyo/`
**Creates**: VPC, RDS, EC2, ALB, WAF, CloudFront (Tokyo-only), TGW (Shinjuku),
Secrets Manager, Route53 origin alias, CloudWatch alarms, SNS topic
**Does NOT create**: TGW peering, cross-region SG rule, CloudFront origin group

```bash
cd lab-3/tokyo/
export TF_VAR_db_password="<your-secure-password>"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Known Issues (Phase 1)

1. **AMI is Ubuntu 22.04, not Amazon Linux** — The `tokyo_ec2_ami_id` in tfvars
   resolves to Ubuntu in ap-northeast-1. The `user_data_tokyo.sh` uses `apt-get`
   (not `yum`). If you see `yum: command not found` in cloud-init logs, the
   user_data script needs the Ubuntu fix.

2. **TGW route table association conflict** — The TGW is created with
   `default_route_table_association = "disable"` and uses an explicit custom
   route table with `replace_existing_association = true`. This avoids the
   `Resource.AlreadyAssociated` error from the default auto-association.

3. **Health check returns 502 initially** — The EC2 instance takes 2-3 minutes
   to install packages and start the Flask app. Wait for the ALB target to show
   `healthy` before testing CloudFront.

**Verify Phase 1**:
```bash
# RDS exists in Tokyo
aws rds describe-db-instances --region ap-northeast-1 \
  --query 'DBInstances[].DBInstanceIdentifier'

# Secret created
aws secretsmanager get-secret-value --secret-id chewbacca/rds/mysql \
  --region ap-northeast-1 --query 'Name'

# TGW exists
aws ec2 describe-transit-gateways --region ap-northeast-1 \
  --query 'TransitGateways[].TransitGatewayId'

# Origin alias resolves
dig origin-tokyo.keepuneat.click +short

# ALB target healthy
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --region ap-northeast-1 \
    --query 'TargetGroups[?TargetGroupName==`chewbacca-tg01`].TargetGroupArn' \
    --output text) --region ap-northeast-1 \
  --query 'TargetHealthDescriptions[].TargetHealth.State'

# App health via CloudFront (wait for target healthy first)
curl -s https://app.keepuneat.click/health
# Expected: {"region":"tokyo","status":"healthy"}

# CloudWatch alarms exist
aws cloudwatch describe-alarms --region ap-northeast-1 \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'
```

**STOP HERE** — Tell MacMini to start Phase 2.

---

## Phase 2: Sao Paulo Apply (MacMini)

**Who**: MacMini
**Dir**: `lab-3/saopaulo/`
**Reads**: Tokyo remote state (TGW ID, VPC CIDR, origin secret)
**Creates**: VPC, EC2, ALB, WAF, TGW (Liberdade), peering REQUEST,
Route53 origin alias, CloudWatch alarms, SNS topic, ALB access logs bucket
**Peering state after**: `pendingAcceptance`

```bash
cd lab-3/saopaulo/
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Verify Phase 2**:
```bash
# SP VPC exists
aws ec2 describe-vpcs --region sa-east-1 \
  --query 'Vpcs[?CidrBlock==`10.76.0.0/16`].VpcId'

# Peering is pending
aws ec2 describe-transit-gateway-peering-attachments --region sa-east-1 \
  --query 'TransitGatewayPeeringAttachments[].State'
# Expected: "pendingAcceptance"

# NO RDS in Sao Paulo (APPI compliance)
aws rds describe-db-instances --region sa-east-1 \
  --query 'DBInstances[]'
# Expected: empty

# ALB exists
aws elbv2 describe-load-balancers --region sa-east-1 \
  --query 'LoadBalancers[].DNSName'

# Origin alias resolves
dig origin-saopaulo.keepuneat.click +short
```

**STOP HERE** — Tell MacPro to start Phase 3.

---

## Phase 3: Tokyo Re-Apply (MacPro)

**Who**: MacPro
**Dir**: `lab-3/tokyo/`
**Reads**: Sao Paulo remote state (ALB DNS, peering attachment ID, VPC CIDR)
**Creates**: TGW peering accepter, TGW static route (10.76.0.0/16 -> SP),
VPC route to SP via TGW, RDS SG rule (MySQL 3306 from SP CIDR),
CloudFront SP origin + origin group failover

### Important: SP Remote State Output Names

The SP state uses **prefixed** output names. The Tokyo locals map them:
- `alb_dns_name` (no prefix)
- `tgw_peering_attachment_id` (no prefix)
- `saopaulo_vpc_cidr` (prefixed with `saopaulo_`)

If you get `"" is not a valid CIDR block` errors, check that `02-locals.tf`
references `saopaulo_vpc_cidr` not `vpc_cidr`.

### CloudFront Origin Group Limitation

Origin groups do NOT support POST/PUT/PATCH/DELETE methods. The
`default_cache_behavior` uses a conditional:
```hcl
allowed_methods = local.phase3_active ? ["GET", "HEAD", "OPTIONS"] : ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
```
This is fine because all app routes use GET (`/health`, `/add?note=`, `/list`, `/init`).

```bash
cd lab-3/tokyo/
export TF_VAR_db_password="<same-password-as-phase-1>"
terraform apply -var="enable_saopaulo_remote_state=true"
```

**Verify Phase 3**:
```bash
# Peering is active
aws ec2 describe-transit-gateway-peering-attachments --region ap-northeast-1 \
  --query 'TransitGatewayPeeringAttachments[].State'
# Expected: "available"

# CloudFront has both origins with https-only
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.DistributionConfig.Origins.Items[*].{Id:Id,Domain:DomainName,Protocol:CustomOriginConfig.OriginProtocolPolicy}'
# Expected: tokyo-alb (origin-tokyo.keepuneat.click, https-only)
#           saopaulo-alb (origin-saopaulo.keepuneat.click, https-only)

# CloudFront origin group exists
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.DistributionConfig.OriginGroups'

# End-to-end health
curl -s https://app.keepuneat.click/health
# Expected: {"region":"tokyo","status":"healthy"}

# RDS only in Tokyo (APPI proof)
aws rds describe-db-instances --region ap-northeast-1 \
  --query 'DBInstances[].DBInstanceIdentifier'
aws rds describe-db-instances --region sa-east-1 \
  --query 'DBInstances[]'
# Expected: empty

# phase3_active output
terraform output phase3_active
# Expected: true
```

---

## CloudWatch Alarms

### Tokyo (ap-northeast-1)

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| `chewbacca-db-connection-failure` | `DBConnectionErrors` (custom) | >= 3 in 5m |
| `chewbacca-rds-cpu-high` | `CPUUtilization` (AWS/RDS) | >= 80% for 10m |
| `chewbacca-rds-storage-low` | `FreeStorageSpace` (AWS/RDS) | <= 1 GB |
| `chewbacca-alb-5xx-high` | `HTTPCode_Target_5XX_Count` | >= 10 in 10m |
| `chewbacca-alb-unhealthy-hosts` | `UnHealthyHostCount` | >= 1 for 1m |

### Sao Paulo (sa-east-1)

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| `liberdade-db-connection-failure` | `DBConnectionErrors` (custom) | >= 3 in 5m |
| `liberdade-alb-5xx-high` | `HTTPCode_Target_5XX_Count` | >= 10 in 10m |
| `liberdade-alb-unhealthy-hosts` | `UnHealthyHostCount` | >= 1 for 1m |

SP does NOT have RDS alarms (no RDS in SP -- APPI compliance).

### Test Alarms

```bash
# Tokyo
aws cloudwatch set-alarm-state \
  --alarm-name "chewbacca-db-connection-failure" \
  --state-value ALARM \
  --state-reason "Manual test for lab documentation" \
  --region ap-northeast-1

# Sao Paulo
aws cloudwatch set-alarm-state \
  --alarm-name "liberdade-alb-unhealthy-hosts" \
  --state-value ALARM \
  --state-reason "Manual test for lab documentation" \
  --region sa-east-1
```

---

## Destroy Order (Reverse)

```bash
# 1. MacPro: Remove Phase 3 cross-region resources
cd lab-3/tokyo/
export TF_VAR_db_password="<password>"
terraform apply -var="enable_saopaulo_remote_state=false"

# 2. MacMini: Destroy Sao Paulo
cd lab-3/saopaulo/
# IMPORTANT: Remove ALB logs bucket from state first (prevent_destroy)
terraform state rm 'aws_s3_bucket.liberdade_alb_logs'
terraform destroy

# 3. MacPro: Destroy Tokyo
cd lab-3/tokyo/
export TF_VAR_db_password="<password>"
terraform destroy
```

---

## Key Details

| Item | Value |
|------|-------|
| S3 Backend Bucket | `class7-armagaggeon-tf-bucket` |
| Tokyo State Key | `lab3/tokyo/terraform.tfstate` |
| SP State Key | `lab3/saopaulo/terraform.tfstate` |
| Tokyo Lock Table | `lab3-tokyo-tf-locks` |
| SP Lock Table | `lab3-saopaulo-tf-locks` |
| Domain | `keepuneat.click` |
| App URL | `https://app.keepuneat.click` |
| Tokyo VPC CIDR | `10.75.0.0/16` |
| SP VPC CIDR | `10.76.0.0/16` |
| Tokyo Origin FQDN | `origin-tokyo.keepuneat.click` |
| SP Origin FQDN | `origin-saopaulo.keepuneat.click` |
| Origin Protocol | `https-only` (both origins) |
| Origin Header | `X-Chewbacca-Growl` (random 32-char secret) |
| Secret Name | `chewbacca/rds/mysql` (ap-northeast-1) |
| DB Password | `TF_VAR_db_password` env var (no default) |
| Tokyo AMI | Ubuntu 22.04 (user_data uses apt-get) |
| CloudFront ID | `E2GBKEHK0L045Y` |
| TGW Tokyo | `tgw-057b23da16e7b2e2c` |

## Lessons Learned

1. **AMI region mismatch**: AMI IDs are region-specific. The `ami-0c02fb55956c7d316`
   (Amazon Linux 2 in us-east-1) resolves to Ubuntu 22.04 in ap-northeast-1.
   Always verify the AMI OS and match your user_data script accordingly.

2. **TGW default route table auto-association**: When creating a custom TGW route
   table, set `default_route_table_association = "disable"` on the TGW resource
   and use `replace_existing_association = true` on the explicit association.
   Otherwise you get `Resource.AlreadyAssociated` errors.

3. **CloudFront https-only requires hostname match**: CloudFront validates the
   origin's TLS cert against the `domain_name` it connects to. Raw ALB DNS names
   (`*.elb.amazonaws.com`) don't match ACM certs for your domain. Solution: create
   Route53 aliases (`origin-tokyo.keepuneat.click`) so the wildcard cert matches.

4. **Origin groups don't support write methods**: CloudFront origin group failover
   only works with GET/HEAD/OPTIONS. POST/PUT/PATCH/DELETE are rejected with
   `InvalidArgument`. Use conditional `allowed_methods` based on `phase3_active`.

5. **SP remote state output names**: SP outputs use the `saopaulo_` prefix
   (e.g., `saopaulo_vpc_cidr`), not bare names. Tokyo's `02-locals.tf` must
   reference the prefixed names or CIDR-dependent resources fail with empty string
   validation errors.

6. **terraform.tfvars must never be tracked**: The `.gitignore` excludes `*.tfvars`.
   If accidentally staged (`git add -f`), remove with `git rm --cached` immediately.
   DB passwords live in `TF_VAR_db_password` env var only.
