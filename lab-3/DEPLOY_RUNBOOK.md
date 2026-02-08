# Lab 3: Split-State Multi-Region Deploy Runbook

## Architecture

```
CloudFront (us-east-1)
    |
    +-- Origin Group (Phase 3)
    |       |
    |       +-- tokyo-alb (primary)     --> EC2 --> RDS (APPI data)
    |       +-- saopaulo-alb (failover) --> EC2 --> [reads Tokyo RDS via TGW]
    |
    +-- TGW Peering: Shinjuku (Tokyo) <--> Liberdade (São Paulo)
```

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
**Creates**: VPC, RDS, EC2, ALB, WAF, CloudFront (Tokyo-only), TGW, Secrets Manager, VPC endpoints
**Does NOT create**: TGW peering, cross-region SG rule, CloudFront origin group

```bash
cd lab-3/tokyo/
export TF_VAR_db_password="<your-secure-password>"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

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

# App health via CloudFront
curl -s https://app.keepuneat.click/health
```

**STOP HERE** — Tell MacMini to start Phase 2.

---

## Phase 2: São Paulo Apply (MacMini)

**Who**: MacMini
**Dir**: `lab-3/saopaulo/`
**Reads**: Tokyo remote state (TGW ID, VPC CIDR, origin secret)
**Creates**: VPC, EC2, ALB, WAF, TGW, peering REQUEST, VPC endpoints, ALB access logs bucket
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

# NO RDS in São Paulo (APPI compliance)
aws rds describe-db-instances --region sa-east-1 \
  --query 'DBInstances[]'
# Expected: empty

# ALB exists
aws elbv2 describe-load-balancers --region sa-east-1 \
  --query 'LoadBalancers[].DNSName'
```

**STOP HERE** — Tell MacPro to start Phase 3.

---

## Phase 3: Tokyo Re-Apply (MacPro)

**Who**: MacPro
**Dir**: `lab-3/tokyo/`
**Reads**: São Paulo remote state (ALB DNS, peering attachment ID, VPC CIDR)
**Creates**: TGW peering accepter, TGW static route, VPC route to SP, RDS SG rule, CloudFront SP origin + origin group

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

# CloudFront has origin group
aws cloudfront list-distributions \
  --query 'DistributionList.Items[].Origins.Items[].Id'
# Expected: tokyo-alb AND saopaulo-alb

# End-to-end health
curl -s https://app.keepuneat.click/health

# RDS only in Tokyo (APPI proof)
aws rds describe-db-instances --region ap-northeast-1 --query 'DBInstances[].DBInstanceIdentifier'
aws rds describe-db-instances --region sa-east-1 --query 'DBInstances[]'  # empty
```

---

## Destroy Order (Reverse)

```bash
# 1. MacPro: Remove Phase 3 cross-region resources
cd lab-3/tokyo/
export TF_VAR_db_password="<password>"
terraform apply -var="enable_saopaulo_remote_state=false"

# 2. MacMini: Destroy São Paulo
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
| Origin Header | `X-Chewbacca-Growl` (random 32-char secret) |
| Secret Name | `chewbacca/rds/mysql` (ap-northeast-1) |
| DB Password | `TF_VAR_db_password` env var (no default) |
