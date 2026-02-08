# Deploy Runbook: Lab 3 - Sao Paulo (Phase 2)

**Region:** `sa-east-1` | **Prefix:** `liberdade_*` | **Machine:** MacMini
**State File:** `s3://class7-armagaggeon-tf-bucket/lab3/saopaulo/terraform.tfstate`
**Lock Table:** `lab3-saopaulo-tf-locks`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Deploy Steps](#3-deploy-steps)
4. [Post-Deploy Verification](#4-post-deploy-verification)
5. [TGW Corridor Verification](#5-tgw-corridor-verification)
6. [CloudWatch Alarm Testing](#6-cloudwatch-alarm-testing)
7. [Teardown Procedure](#7-teardown-procedure)
8. [Deployed Resource Inventory](#8-deployed-resource-inventory)
9. [Troubleshooting & Lessons Learned](#9-troubleshooting--lessons-learned)
10. [Cross-Machine Coordination](#10-cross-machine-coordination)

---

## 1. Architecture Overview

```
                 CloudFront (us-east-1)
                    Origin Group
                   /            \
          primary /              \ failover (5xx)
                 /                \
  origin-tokyo.keepuneat.click   origin-saopaulo.keepuneat.click
         Tokyo ALB                   SP ALB (liberdade_alb01)
            |                            |
       Tokyo EC2                     SP EC2 (10.76.101.89)
            |                            |
       Tokyo RDS  <---- TGW Peering ---->|
    (10.75.128.162)     (cross-region)
         ^
         |
    Data Authority
    (APPI Compliant)
```

**APPI Compliance:** Sao Paulo is stateless compute only. No RDS, no PHI storage.
The Flask app reads secrets cross-region from Tokyo Secrets Manager via IAM + boto3,
then connects to Tokyo RDS over the TGW peering corridor.

---

## 2. Prerequisites

Before running `terraform apply` in `lab-3/saopaulo/`:

| Prerequisite | How to verify |
|---|---|
| Tokyo Phase 1 deployed | `aws s3 ls s3://class7-armagaggeon-tf-bucket/lab3/tokyo/terraform.tfstate` |
| DynamoDB lock table exists | `aws dynamodb describe-table --table-name lab3-saopaulo-tf-locks --region sa-east-1` |
| Route53 zone `keepuneat.click` exists | `aws route53 list-hosted-zones --query 'HostedZones[?Name==\`keepuneat.click.\`]'` |
| `terraform.tfvars` exists locally | `ls lab-3/saopaulo/terraform.tfvars` (NOT in git) |
| AWS credentials configured | `aws sts get-caller-identity` (Account: ***REDACTED_ACCOUNT_ID***) |

---

## 3. Deploy Steps

### 3a. First-Time Deploy

```bash
cd lab-3/saopaulo/

# Initialize backend (connects to S3 state + DynamoDB lock)
terraform init

# Preview changes
terraform plan -out=tfplan

# Apply (expect ~60 resources)
terraform apply tfplan
```

### 3b. Post-Phase-3 Re-Apply

After MacPro accepts TGW peering in Tokyo Phase 3, the SP static route
becomes activatable. If `15-tgw-peering.tf` still has `count = 0` on the
static route, remove it and re-apply:

```bash
# Verify peering is accepted first
aws ec2 describe-transit-gateway-peering-attachments --region sa-east-1 \
  --query 'TransitGatewayPeeringAttachments[0].State'
# Must show: "available"

# Then apply to create the static route
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 4. Post-Deploy Verification

Run these checks after every apply:

```bash
# 1. VPC exists with correct CIDR
aws ec2 describe-vpcs --region sa-east-1 \
  --query 'Vpcs[?CidrBlock==`10.76.0.0/16`].{ID:VpcId,CIDR:CidrBlock}' --output table

# 2. EC2 instance running in private subnet
aws ec2 describe-instances --region sa-east-1 \
  --filters "Name=tag:Name,Values=*liberdade*" "Name=instance-state-name,Values=running" \
  --query 'Instances[].{ID:InstanceId,IP:PrivateIpAddress,State:State.Name}' --output table

# 3. ALB exists and is active
aws elbv2 describe-load-balancers --region sa-east-1 \
  --query 'LoadBalancers[?LoadBalancerName==`liberdade-alb01`].{DNS:DNSName,State:State.Code}' --output table

# 4. WAF attached to ALB
aws wafv2 list-web-acls --region sa-east-1 --scope REGIONAL \
  --query 'WebACLs[?Name==`liberdade-sp-waf01`].{Name:Name,ARN:ARN}' --output table

# 5. ALB logs bucket exists
aws s3 ls s3://liberdade-alb-logs-***REDACTED_ACCOUNT_ID***/ 2>&1 && echo "BUCKET EXISTS" || echo "MISSING"

# 6. Origin DNS resolves
dig +short origin-saopaulo.keepuneat.click

# 7. No RDS in SP (APPI compliance)
aws rds describe-db-instances --region sa-east-1 \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
# Expected: empty

# 8. SNS subscription confirmed
aws sns list-subscriptions-by-topic --region sa-east-1 \
  --topic-arn "arn:aws:sns:sa-east-1:***REDACTED_ACCOUNT_ID***:liberdade-alb-incidents" \
  --query 'Subscriptions[].{Endpoint:Endpoint,Status:SubscriptionArn}' --output table

# 9. CloudWatch alarms exist
aws cloudwatch describe-alarms --region sa-east-1 \
  --alarm-name-prefix "liberdade-" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' --output table
```

---

## 5. TGW Corridor Verification

These tests prove the cross-region TGW peering between SP and Tokyo is functional.

### Test 1: Peering State

```bash
# Both sides must show "available"
aws ec2 describe-transit-gateway-peering-attachments --region sa-east-1 \
  --query 'TransitGatewayPeeringAttachments[0].State'

aws ec2 describe-transit-gateway-peering-attachments --region ap-northeast-1 \
  --query 'TransitGatewayPeeringAttachments[0].State'
```

### Test 2: TGW Route Tables

```bash
# SP TGW default RT — must have static route to 10.75.0.0/16
SP_RT=$(aws ec2 describe-transit-gateway-route-tables --region sa-east-1 \
  --query 'TransitGatewayRouteTables[?DefaultAssociationRouteTable==`true`].TransitGatewayRouteTableId' --output text)

aws ec2 search-transit-gateway-routes --region sa-east-1 \
  --transit-gateway-route-table-id "$SP_RT" \
  --filters "Name=type,Values=static,propagated" \
  --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,State:State}' --output table

# Tokyo TGW RT — must have static route to 10.76.0.0/16
# Find the RT that has both VPC and peering associated
for rt in $(aws ec2 describe-transit-gateway-route-tables --region ap-northeast-1 \
  --query 'TransitGatewayRouteTables[].TransitGatewayRouteTableId' --output text); do
  echo "=== $rt ==="
  aws ec2 search-transit-gateway-routes --region ap-northeast-1 \
    --transit-gateway-route-table-id "$rt" \
    --filters "Name=type,Values=static,propagated" \
    --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,State:State}' --output table 2>&1
done
```

### Test 3: VPC Route Tables

```bash
# SP private RT must route 10.75.0.0/16 via TGW
aws ec2 describe-route-tables --region sa-east-1 \
  --filters "Name=tag:Name,Values=*liberdade*private*" \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.75.0.0/16`].{CIDR:DestinationCidrBlock,TGW:TransitGatewayId,State:State}' \
  --output table

# Tokyo private RT must route 10.76.0.0/16 via TGW
aws ec2 describe-route-tables --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=*chewbacca*private*" \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.76.0.0/16`].{CIDR:DestinationCidrBlock,TGW:TransitGatewayId,State:State}' \
  --output table
```

### Test 4: RDS Security Group

```bash
# Tokyo RDS SG must allow 10.76.0.0/16 on port 3306
aws ec2 describe-security-groups --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=*rds*" \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`3306`].IpRanges[].{CIDR:CidrIp}' --output table
```

### Test 5: Live TCP Connectivity (SSM)

```bash
# Get SP EC2 instance ID
SP_INSTANCE=$(aws ec2 describe-instances --region sa-east-1 \
  --filters "Name=tag:Name,Values=*liberdade*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[0].InstanceId' --output text)

# Get Tokyo RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --region ap-northeast-1 \
  --query 'DBInstances[0].Endpoint.Address' --output text)

# Send TCP test via SSM
CMD_ID=$(aws ssm send-command --region sa-east-1 \
  --instance-ids "$SP_INSTANCE" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"echo Test: SP EC2 to Tokyo RDS via TGW\",
    \"echo Target: ${RDS_ENDPOINT}:3306\",
    \"timeout 10 bash -c 'echo > /dev/tcp/${RDS_ENDPOINT}/3306' 2>&1 && echo CONNECTION_SUCCESS || echo CONNECTION_FAILED\"
  ]" --query 'Command.CommandId' --output text)

# Wait and fetch result
sleep 15
aws ssm get-command-invocation --region sa-east-1 \
  --command-id "$CMD_ID" --instance-id "$SP_INSTANCE" \
  --query '{Status:Status,Output:StandardOutputContent}' --output json
```

**Expected result:** `CONNECTION_SUCCESS`

---

## 6. CloudWatch Alarm Testing

### Fire All Alarms (Manual Test)

```bash
# ALB 5xx alarm
aws cloudwatch set-alarm-state --region sa-east-1 \
  --alarm-name "liberdade-alb-5xx-high" \
  --state-value ALARM --state-reason "Manual test"

# Unhealthy hosts alarm
aws cloudwatch set-alarm-state --region sa-east-1 \
  --alarm-name "liberdade-alb-unhealthy-hosts" \
  --state-value ALARM --state-reason "Manual test"

# DB connection failure alarm
aws cloudwatch set-alarm-state --region sa-east-1 \
  --alarm-name "liberdade-db-connection-failure" \
  --state-value ALARM --state-reason "Manual test"
```

### Verify Alarm States

```bash
aws cloudwatch describe-alarms --region sa-east-1 \
  --alarm-name-prefix "liberdade-" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Updated:StateUpdatedTimestamp}' \
  --output table
```

### Reset All Alarms

```bash
for alarm in "liberdade-alb-5xx-high" "liberdade-alb-unhealthy-hosts" "liberdade-db-connection-failure"; do
  aws cloudwatch set-alarm-state --region sa-east-1 \
    --alarm-name "$alarm" --state-value OK --state-reason "Reset after test"
done
```

---

## 7. Teardown Procedure

**Order matters.** The ALB logs bucket has `prevent_destroy = true`.

```bash
cd lab-3/saopaulo/

# Step 1: Remove the protected bucket from state FIRST
terraform state rm 'aws_s3_bucket.liberdade_alb_logs'

# Step 2: Destroy everything else
terraform destroy

# Step 3: Empty and delete the bucket manually (if desired)
aws s3 rm s3://liberdade-alb-logs-***REDACTED_ACCOUNT_ID*** --recursive --region sa-east-1
aws s3 rb s3://liberdade-alb-logs-***REDACTED_ACCOUNT_ID*** --region sa-east-1
```

**WARNING:** Do NOT run `terraform destroy` without Step 1. It will fail on the
protected bucket and leave the state in a partial-destroy mess.

---

## 8. Deployed Resource Inventory

**Total:** 63 managed resources (60 resources + 5 data sources - 2 removed during TGW fix)

### Networking (17 resources)
| Resource | Name/ID |
|---|---|
| VPC | `vpc-01adf59fe5cd62857` (10.76.0.0/16) |
| Public Subnet 1 | `subnet-0f2f902dd855caca5` (sa-east-1a) |
| Public Subnet 2 | `subnet-0f563f308c48917d7` (sa-east-1c) |
| Private Subnet 1 | `subnet-022830f5a6bf4a597` (sa-east-1a) |
| Private Subnet 2 | `subnet-0295217a29bd6e725` (sa-east-1c) |
| IGW | `liberdade_igw01` |
| NAT GW | `liberdade_nat01` + EIP |
| Public RT | `liberdade_public_rt01` + 2 associations |
| Private RT | `liberdade_private_rt01` + 2 associations + TGW route |

### Compute (5 resources)
| Resource | Name/ID |
|---|---|
| EC2 | `i-0a2a60715a2f2e4f6` (t3.micro, private subnet, 10.76.101.89) |
| IAM Role | `liberdade_ec2_role01` (SSM + CW + cross-region Secrets Manager) |
| Instance Profile | `liberdade_instance_profile01` |

### Load Balancer (8 resources)
| Resource | Name/ID |
|---|---|
| ALB | `liberdade-alb01` (public subnets, access logs enabled) |
| Target Group | `liberdade_tg01` (HTTP :80, health: `/health`) |
| HTTP Listener | `:80` redirect to HTTPS |
| HTTPS Listener | `:443` default deny |
| Origin Cloaking Rule | Allow if X-Chewbacca-Growl header matches |
| Default Block Rule | Fixed 403 for requests without valid header |
| ACM Certificate | `*.keepuneat.click` + DNS validation records |

### Security (4 resources)
| Resource | Name/ID |
|---|---|
| EC2 SG | HTTP :80 from ALB SG only, no SSH (SSM only) |
| ALB SG | HTTPS :443 from CloudFront prefix list |
| VPCE SG | HTTPS :443 from EC2 SG |
| WAF | `liberdade-sp-waf01` (IP rep, common, bad inputs, SQLi) |

### Transit Gateway (4 resources)
| Resource | Name/ID |
|---|---|
| TGW | `tgw-082eb2bf890ba9980` (default RT, auto-associate) |
| VPC Attachment | `liberdade_attach_sp_vpc01` |
| Peering Attachment | `tgw-attach-0d30f46b569c358d6` (to Tokyo, state: available) |
| Static Route | `10.75.0.0/16` via peering attachment |

### VPC Endpoints (6 resources)
| Resource | Type |
|---|---|
| S3 | Gateway endpoint |
| SSM | Interface endpoint |
| SSM Messages | Interface endpoint |
| EC2 Messages | Interface endpoint |
| CloudWatch Logs | Interface endpoint |
| CloudWatch Monitoring | Interface endpoint |

### Monitoring (5 resources)
| Resource | Name |
|---|---|
| SNS Topic | `liberdade-alb-incidents` |
| SNS Subscription | `gaijinmzungu@gmail.com` (email, confirmed) |
| Alarm: ALB 5xx | `liberdade-alb-5xx-high` (threshold: 10, 2 eval periods) |
| Alarm: Unhealthy Hosts | `liberdade-alb-unhealthy-hosts` (threshold: 1) |
| Alarm: DB Conn Errors | `liberdade-db-connection-failure` (threshold: 3) |

### Storage (6 resources)
| Resource | Name |
|---|---|
| S3 Bucket | `liberdade-alb-logs-***REDACTED_ACCOUNT_ID***` (prevent_destroy) |
| Bucket Policy | ELB account 507241528517 write access |
| Encryption | AES256 SSE |
| Versioning | Enabled |
| Lifecycle | 90-day expiration |
| Public Access Block | All blocked |

### DNS (1 resource)
| Resource | Name |
|---|---|
| Route53 A Alias | `origin-saopaulo.keepuneat.click` -> SP ALB |

---

## 9. Troubleshooting & Lessons Learned

### TGW Default RT Conflict
**Problem:** `terraform apply` fails with "Transit Gateway Attachment is already associated to a route table."
**Cause:** TGW has `default_route_table_association = "enable"` which auto-associates new attachments. Creating an explicit `aws_ec2_transit_gateway_route_table_association` conflicts.
**Fix:** Use the default route table only. Remove custom RT, explicit association, and propagation resources. Reference the default RT via `aws_ec2_transit_gateway.liberdade_tgw01.association_default_route_table_id`.

### TGW Static Route Before Peering Accepted
**Problem:** `terraform apply` fails with "attachment is in invalid state."
**Cause:** Can't create a TGW static route through a peering attachment that is `pendingAcceptance`.
**Fix:** Gate the route with `count = 0` until Phase 3 accepts the peering, then remove the count and re-apply.

### TGW Peering Must Be Associated on BOTH Sides
**Problem:** All route tables and VPC routes look correct, but live TCP test fails (CONNECTION FAILED).
**Cause:** The peering attachment on the Tokyo side was not associated with any TGW route table. Traffic arriving from SP entered Tokyo's TGW but had no routing decision — blackholed.
**Fix:** Associate the peering attachment with Tokyo's TGW route table that contains the VPC propagated route. This was done via CLI as a hotfix:
```bash
aws ec2 associate-transit-gateway-route-table --region ap-northeast-1 \
  --transit-gateway-route-table-id tgw-rtb-0d5737a98b213a2b7 \
  --transit-gateway-attachment-id tgw-attach-0d30f46b569c358d6
```
**Action:** MacPro must add `aws_ec2_transit_gateway_route_table_association` to Tokyo TF and `terraform import` it.

### terraform.tfvars in Git
**Problem:** `git add -f` overrides `.gitignore` and pushes secrets to public repo.
**Fix:** `git rm --cached lab-3/saopaulo/terraform.tfvars` to untrack while keeping local copy. Verify with `git check-ignore -v lab-3/saopaulo/terraform.tfvars`.

### CloudFront SSL Mismatch
**Problem:** CloudFront failover to SP ALB gets SSL 502 when using raw ALB DNS name as origin.
**Cause:** ACM cert is `*.keepuneat.click` but ALB DNS is `liberdade-alb01-xxx.sa-east-1.elb.amazonaws.com` — hostname mismatch.
**Fix:** Create Route53 A alias `origin-saopaulo.keepuneat.click` pointing to SP ALB. Use this FQDN as the CloudFront failover origin.

---

## 10. Cross-Machine Coordination

### What SP Exports (for Tokyo Phase 3)

| Output | Value | Used By |
|---|---|---|
| `tgw_peering_attachment_id` | `tgw-attach-0d30f46b569c358d6` | Tokyo peering accepter |
| `saopaulo_tgw_id` | `tgw-082eb2bf890ba9980` | Tokyo TGW references |
| `alb_dns_name` | `liberdade-alb01-xxx.sa-east-1.elb.amazonaws.com` | CloudFront origin group |
| `origin_fqdn` | `origin-saopaulo.keepuneat.click` | CloudFront failover origin (SSL-safe) |
| `saopaulo_vpc_cidr` | `10.76.0.0/16` | Tokyo RDS SG ingress, TGW routes |

### What SP Reads from Tokyo (remote state)

| Output | Used For |
|---|---|
| `tgw_id` | Peering attachment target |
| `vpc_cidr` | TGW static route destination (10.75.0.0/16) |
| `origin_secret` | Origin cloaking X-Chewbacca-Growl header value |

### Outstanding Tokyo-Side Action Items

1. **Import peering RT association** — CLI hotfix needs Terraform state:
   ```bash
   # In Tokyo TF, add:
   # resource "aws_ec2_transit_gateway_route_table_association" "peering_to_rt" { ... }
   terraform import aws_ec2_transit_gateway_route_table_association.peering_to_rt \
     tgw-attach-0d30f46b569c358d6_tgw-rtb-0d5737a98b213a2b7
   ```

2. **CloudFront origin group** — Add SP as failover origin using `origin-saopaulo.keepuneat.click`
