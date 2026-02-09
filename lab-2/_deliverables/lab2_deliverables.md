# Lab 2 Deliverables — Vandelay Industries (us-east-1)

**Date**: 2026-02-09
**Student**: Niko Farias
**Domain**: keepuneat.click
**CloudFront Distribution**: E1FJJ49BOKLK9R (d3pg9mxlde5cap.cloudfront.net)
**Region**: us-east-1

---

## Lab 2A: Origin Cloaking + CloudFront

### 1. Origin Cloaking Proof — Direct ALB Access Blocked

The ALB security group (`vandelay-alb-sg01`, `sg-0faf84816f927d11d`) restricts ingress to **only** the CloudFront managed prefix list (`pl-3b927c52`). Direct access to the ALB times out at the network level:

```
$ curl -sI --connect-timeout 10 http://vandelay-alb01-212107261.us-east-1.elb.amazonaws.com/
(Connection timed out — SG blocks non-CloudFront traffic)

$ curl -sI --connect-timeout 10 https://vandelay-alb01-212107261.us-east-1.elb.amazonaws.com/
(Connection timed out — SG blocks non-CloudFront traffic)
```

**ALB Security Group Ingress Rules:**
```json
{
    "Name": "vandelay-alb-sg01",
    "Ingress": [
        {
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "PrefixListIds": [
                {
                    "Description": "Allow HTTP from CloudFront origin-facing IPs only",
                    "PrefixListId": "pl-3b927c52"
                }
            ]
        }
    ]
}
```

### 2. CloudFront Access — 200 OK

```
$ curl -sI https://app.keepuneat.click
HTTP/2 200
content-type: text/html; charset=utf-8
content-length: 166
date: Mon, 09 Feb 2026 06:00:26 GMT
server: Werkzeug/3.1.5 Python/3.9.25
x-cache: Miss from cloudfront
via: 1.1 3cf7ab833147270a70632e08b50803d6.cloudfront.net (CloudFront)
x-amz-cf-pop: DEN53-P5
```

### 3. ALB Listener Rules — Header Validation + 403 Catch-All

```json
[
    {
        "Priority": "10",
        "Conditions": [
            {
                "Field": "http-header",
                "HttpHeaderConfig": {
                    "HttpHeaderName": "X-Vandelay-Secret",
                    "Values": ["B9qmoHWWocUY0yKc88Ao1pZx2LL7Js7R"]
                }
            }
        ],
        "Actions": { "Type": "forward" }
    },
    {
        "Priority": "99",
        "Conditions": [{ "Field": "path-pattern", "Values": ["*"] }],
        "Actions": {
            "Type": "fixed-response",
            "FixedResponseConfig": {
                "MessageBody": "Forbidden - Access denied",
                "StatusCode": "403",
                "ContentType": "text/plain"
            }
        }
    }
]
```

**Two-layer origin cloaking:**
1. **Network layer**: ALB SG only allows CloudFront prefix list IPs
2. **Application layer**: ALB listener requires `X-Vandelay-Secret` header; returns 403 otherwise

### 4. DNS Proof

```
$ dig app.keepuneat.click A +short
99.84.118.94
99.84.118.37
99.84.118.23
99.84.118.60

$ dig d3pg9mxlde5cap.cloudfront.net A +short
99.84.118.94
99.84.118.60
99.84.118.37
99.84.118.23
```

`app.keepuneat.click` resolves to the same IPs as the CloudFront distribution.

### 5. WAF on CloudFront

```json
{
    "Name": "vandelay-cf-waf01",
    "Id": "81b74ebb-cbc3-40fe-9408-6be30dddf283",
    "Rules": [
        { "Name": "AWS-AWSManagedRulesAmazonIpReputationList", "Priority": 0 },
        { "Name": "AWS-AWSManagedRulesCommonRuleSet", "Priority": 1 },
        { "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet", "Priority": 2 },
        { "Name": "AWS-AWSManagedRulesSQLiRuleSet", "Priority": 3 }
    ]
}
```

### 6. WAF on ALB (Regional)

```json
{
    "Name": "vandelay-waf01",
    "Rules": [
        { "Name": "AWS-AWSManagedRulesAmazonIpReputationList", "Priority": 0 },
        { "Name": "AWS-AWSManagedRulesCommonRuleSet", "Priority": 1 },
        { "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet", "Priority": 2 },
        { "Name": "AWS-AWSManagedRulesSQLiRuleSet", "Priority": 3 }
    ]
}
```

---

## Lab 2B: Cache Correctness

### 1. API Requests — No Caching (CachingDisabled policy)

Both requests show `x-cache: Miss from cloudfront`, confirming API responses are not cached:

```
$ curl -sI https://app.keepuneat.click/list
HTTP/2 200
content-type: text/html; charset=utf-8
date: Mon, 09 Feb 2026 06:05:29 GMT
x-cache: Miss from cloudfront

$ curl -sI https://app.keepuneat.click/list  (3s later)
HTTP/2 200
content-type: text/html; charset=utf-8
date: Mon, 09 Feb 2026 06:05:32 GMT
x-cache: Miss from cloudfront
```

### 2. Home Page Requests — Cache Behavior

```
$ curl -sI https://app.keepuneat.click/
HTTP/2 200
x-cache: Miss from cloudfront

$ curl -sI https://app.keepuneat.click/  (3s later)
HTTP/2 200
x-cache: Miss from cloudfront
```

### 3. Cache Policies Applied

| Behavior | Cache Policy | Purpose |
|----------|-------------|---------|
| Default (*) | CachingDisabled (4135ea2d) | API/dynamic: never cache |
| Static (/static/*) | Custom vandelay-cache-static01 (8aa37f03) | Cache static assets with query string key |

---

## CRUD Verification

```
$ curl -s https://app.keepuneat.click/health
{"status":"healthy"}

$ curl -s https://app.keepuneat.click/init
{"status":"Database initialized successfully"}

$ curl -s "https://app.keepuneat.click/add?note=test-note-1"
{"message":"Note added: test-note-1","status":"success"}

$ curl -s "https://app.keepuneat.click/add?note=lab2-deliverable-test"
{"message":"Note added: lab2-deliverable-test","status":"success"}

$ curl -s https://app.keepuneat.click/list
<h2>Notes</h2><ul>
<li>[1] test-note-1 - 2026-02-09 05:54:32</li>
<li>[2] lab2-deliverable-test - 2026-02-09 05:54:32</li>
</ul>
```

---

## Gate Script Results

All gates passed with **GREEN** badge.

### Gate 1: Secrets + EC2 Role Verification (PASS)

```
Region:          us-east-1
Instance ID:     i-01e26a1aa17773ef2
Secret ID:       lab/rds/mysql
Resolved Role:   vandelay-ec2-role01

PASS: aws sts get-caller-identity succeeded (credentials OK).
PASS: secret exists and is describable (lab/rds/mysql).
PASS: secret rotation enabled (lab/rds/mysql).
PASS: no resource policy found (OK) or not applicable (lab/rds/mysql).
PASS: instance has IAM instance profile attached (i-01e26a1aa17773ef2).
PASS: resolved instance profile -> role (vandelay-instance-profile01 -> vandelay-ec2-role01).

RESULT: PASS
```

### Gate 2: Network + RDS Verification (PASS)

```
EC2 Instance:    i-01e26a1aa17773ef2
RDS Instance:    vandelay-rds01
Engine:          mysql
DB Port:         3306

PASS: aws sts get-caller-identity succeeded (credentials OK).
PASS: RDS instance exists (vandelay-rds01).
PASS: RDS is not publicly accessible (PubliclyAccessible=False).
PASS: discovered DB port = 3306 (engine=mysql).
PASS: EC2 security groups resolved: sg-00ab03372f8bbc21b
PASS: RDS security groups resolved: sg-0849ab514b5f93268
PASS: RDS SG allows DB port 3306 from EC2 SG (SG-to-SG ingress present).
PASS: subnet subnet-0e86804be9205e8e0 shows no IGW route (private check OK).
PASS: subnet subnet-09a3a4af6ad3e5e69 shows no IGW route (private check OK).

RESULT: PASS
```

### Combined Gate Summary

```
Gate 1 (secrets_and_role) exit: 0
Gate 2 (network_db)       exit: 0
BADGE:  GREEN
RESULT: PASS
```

---

## Infrastructure Evidence

### CloudWatch Alarms

| Alarm Name | State | Metric |
|-----------|-------|--------|
| vandelay-alb-5xx-alarm | OK | HTTPCode_ELB_5XX_Count |
| vandelay-db-connection-failure | OK | DBConnectionErrors |

### VPC Endpoints (8 total)

| Service | Type | State |
|---------|------|-------|
| com.amazonaws.us-east-1.s3 | Gateway | available |
| com.amazonaws.us-east-1.monitoring | Interface | available |
| com.amazonaws.us-east-1.secretsmanager | Interface | available |
| com.amazonaws.us-east-1.logs | Interface | available |
| com.amazonaws.us-east-1.ssm | Interface | available |
| com.amazonaws.us-east-1.kms | Interface | available |
| com.amazonaws.us-east-1.ec2messages | Interface | available |
| com.amazonaws.us-east-1.ssmmessages | Interface | available |

### Security Groups

| SG Name | SG ID | Purpose |
|---------|-------|---------|
| vandelay-alb-sg01 | sg-0faf84816f927d11d | ALB — CloudFront prefix list only |
| vandelay-ec2-sg01 | sg-00ab03372f8bbc21b | EC2 — HTTP from ALB SG, SSH from 0.0.0.0/0 |
| vandelay-rds-sg01 | sg-0849ab514b5f93268 | RDS — MySQL 3306 from EC2 SG only |

### Terraform Outputs

```
ec2_instance_id              = "i-01e26a1aa17773ef2"
ec2_public_ip                = "54.161.218.222"
rds_endpoint                 = "vandelay-rds01.cmrys4aosktq.us-east-1.rds.amazonaws.com"
rds_port                     = 3306
vandelay_cloudfront_id       = "E1FJJ49BOKLK9R"
vandelay_cloudfront_domain   = "d3pg9mxlde5cap.cloudfront.net"
vandelay_vpc_id              = "vpc-01ca9d1aae894543a"
vandelay_origin_cloaking_enabled = true
secret_name                  = "lab/rds/mysql"
secret_rotation_enabled      = true
iam_role_name                = "vandelay-ec2-role01"
incident_reporter_function_name = "vandelay-incident-reporter"
incident_reports_bucket      = "vandelay-incident-reports-212809501772"
sns_topic_arn                = "arn:aws:sns:us-east-1:212809501772:vandelay-db-incidents"
vandelay_cf_waf_arn          = "arn:aws:wafv2:us-east-1:212809501772:global/webacl/vandelay-cf-waf01/..."
vandelay_waf_log_group_name  = "aws-waf-logs-vandelay-webacl"
```

### Terraform Resource Summary (105 resources)

| Category | Count | Key Resources |
|----------|-------|---------------|
| Networking | 18 | VPC, 4 subnets, IGW, NAT, 2 route tables, 4 RT associations, EIP |
| Compute | 4 | 2 EC2 instances (public + private bonus), instance profile, IAM role |
| Database | 3 | RDS MySQL (db.t3.micro), DB subnet group, RDS SG |
| Load Balancing | 7 | ALB, 2 listeners, 2 listener rules, target group, TG attachment |
| CloudFront | 7 | Distribution, cache policy, ORP, response headers policy, cache invalidation |
| WAF | 4 | 2 WebACLs (CF + ALB), WAF-ALB association, WAF logging config |
| DNS/TLS | 6 | ACM cert, cert validation, 3 Route53 records, hosted zone data |
| Secrets/Params | 10 | Secret rotation, 6 SSM params, rotation Lambda CFN stack |
| Security Groups | 6 | ALB SG, EC2 SG, RDS SG, VPCE SG x2, rotation Lambda SG |
| VPC Endpoints | 8 | S3 (GW), SSM, SSM Messages, EC2 Messages, Logs, KMS, Monitoring, Secrets Manager |
| IAM | 16 | EC2 role, rotation role, incident reporter role, policies, attachments |
| Lambda | 4 | Incident reporter function, permissions, SNS subscription |
| Monitoring | 4 | CloudWatch log group, dashboard, 2 metric alarms |
| S3 | 4 | Incident reports bucket + versioning + encryption + public access block |
| SNS | 3 | Topic, email subscription, Lambda subscription |

---

## Architecture Notes

- **Origin cloaking** is implemented at two layers: SG prefix list (network) + secret header validation (application)
- **RDS** is in private subnets with no IGW route — verified by gate scripts
- **Secrets Manager** with automatic rotation via Lambda
- **8 VPC endpoints** ensure private connectivity for SSM, Secrets Manager, CloudWatch, KMS, S3
- **Dual WAF** coverage: CloudFront WAF (CLOUDFRONT scope) + ALB WAF (REGIONAL scope), both with IP reputation, CRS, known bad inputs, and SQLi rules
- **Incident reporter** Lambda triggered by SNS from CloudWatch alarms, uses Bedrock Claude for analysis

---

## Deliverable Files

| File | Description |
|------|-------------|
| `lab2_deliverables.md` | This report |
| `gate_result.json` | Combined gate results (GREEN/PASS) |
| `gate_secrets_and_role.json` | Gate 1: secrets + IAM role verification |
| `gate_network_db.json` | Gate 2: network + RDS verification |
