# Lab-2 Vandelay - DevOps - Jenkins - Infrastructure — Team Handoff Report
__________

**Date:** 2026-03-29 | **Author:** NRD808Sequence | **Status:** Paused — Cost Optimization Mode

---

## Executive Summary

We successfully built, debugged, and validated a **full CI/CD pipeline** for the Vandelay Lab-2 AWS infrastructure stack. The pipeline runs Terraform plan/apply through Jenkins, gated by human approval, and is now **webhook-driven from GitHub** — meaning every code push automatically triggers a pipeline run. The stack has been partially torn down to cut costs while preserving all pipeline intelligence.

**Bottom line:** Infrastructure-as-Code is working. The pipeline is proven. We are paused — not stuck.

---

## What Was Built

### Infrastructure Stack (Terraform-managed)

|Component|Purpose|State|
|---|---|---|
|VPC + subnets (public/private)|Network foundation|**Up** — $0 idle|
|EC2 app server|Flask → RDS notes app|**Destroyed**|
|RDS MySQL 8.4|Database backend|**Destroyed**|
|ALB + WAF|Load balancer + web firewall|**Destroyed**|
|NAT Gateway|Private subnet egress|**Destroyed**|
|CloudFront + Route53|CDN + DNS (`keepuneat.click`)|**Up** — $0 idle|
|Secrets Manager|RDS credentials (no hardcoding)|**Up** — $0 idle|
|Jenkins EC2 (t3.medium)|CI/CD server|**Stopped** — $0/hr|
|Jenkins EBS (20GB gp3)|Persistent home volume|**Attached** — $1.60/mo|
|S3 (TF state + ALB logs)|Backend state + audit trail|**Up** — <$1/mo|

### Pipeline (Jenkinsfile — 10 stages)

```
GitHub Push → Webhook → Jenkins
  1. Checkout       ✓
  2. TF Init        ✓
  3. TF Validate    ✓
  4. TF Plan        ✓  (plan artifact archived)
  5. Approval Gate  ✓  (human must approve before AWS changes)
  6. TF Apply       ✓
  7. Extract Outputs ✓
  8. Smoke Test     ✓  (HTTP 200 check)
  9. Gate Tests     ✓  (Secrets Manager + IAM + RDS network checks)
 10. Notify         ✓
```

### Key Security Controls Implemented

- DB password injected via Jenkins `withCredentials` — never in code
- ALB origin cloaking (CloudFront-only traffic via header rule)
- WAF rules: rate limiting + WordPress path blocking + managed rule groups
- Approval gate enforced on **all** webhook-triggered deploys — automation can't bypass it
- `.tfvars` with secrets gitignored — never committed

---

## Current AWS Billing State

|Resource|Status|Monthly Cost|
|---|---|---|
|Jenkins EC2 (stopped)|Stopped|**$0/hr** while stopped|
|Jenkins EBS 20GB|Attached|**~$1.60**|
|EIP `44.194.126.118`|**Unattached — billing**|**~$3.60**|
|EIP `52.1.218.143`|**Unattached — billing**|**~$3.60**|
|S3, VPC, IAM, CloudFront|Idle|**<$1**|
|**Total while paused**||**~$10/mo**|
|**Total when running**||**~$90/mo**|

> **Action required now:** Release both unattached EIPs — saving $7.20/mo for zero benefit while paused.

---

## What Is Proven vs. What Is Pending

### ✅ Proven (high confidence)

- **Webhook → Build trigger:** Build #8 shows `GitHubPushCause: Started by GitHub push by NRD808Sequence` — not manual, not CLI
- **Credential injection:** `TF_VAR_db_password` correctly delivered via `withCredentials` — no more "No value for required variable" failures
- **Full pipeline SUCCESS:** Builds #5 and #7 completed `Apply → Smoke Test → Gate Tests → SUCCESS`
- **Infra idempotent:** `No changes. Your infrastructure matches the configuration.` on clean re-runs

### ⚠️ Known Issues (before next spin-up)

1. **EBS remount failure** — When Jenkins EC2 was last replaced, the persistent EBS volume (`/dev/nvme2n1`) didn't mount at boot. Jenkins home landed on the root volume instead. This means if the EC2 is **terminated** (not just stopped), plugins/jobs are lost again.  
    _Fix needed in `jenkins_user_data.sh`: probe additional NVMe device names (`nvme2n1`, `nvme3n1`)._
    
2. **Jenkins IP changes on restart** — Every time the EC2 starts, it gets a new public IP. The GitHub webhook is hardcoded to `http://107.21.10.233:8080`.  
    _Fix: Allocate a dedicated EIP for Jenkins and attach it, so the URL is stable._
    
3. **`vandelay-db-password` credential lives in Jenkins only** — Not backed up anywhere. If Jenkins is ever wiped, this needs to be re-entered.  
    _Value is in local `lab-2/terraform.tfvars` (gitignored)._
    

---

## Pre-Spin-Up Checklist

Run through this in order before the next `terraform apply`:

```
□ 1. Release the 2 unattached EIPs (do this now — they're billing)
□ 2. Allocate a fresh EIP and assign it to Jenkins in terraform.tfvars
      → Prevents webhook URL breaking on every restart
□ 3. Fix jenkins_user_data.sh EBS device probe
      → Add nvme2n1, nvme3n1 to the device detection loop
□ 4. Start Jenkins EC2 (aws ec2 start-instances)
□ 5. Verify Jenkins UI is up at new IP:8080
□ 6. Re-enter vandelay-db-password credential (if not already there)
□ 7. Update GitHub webhook URL to new Jenkins IP
      → https://github.com/Class-6-Hungry-Wolves/Class-7-Armageddon/settings/hooks/603380916
□ 8. Run terraform apply (full stack redeploy)
□ 9. Trigger a push to nikrdf-armageddon-branch
□ 10. Confirm Build fires with GitHubPushCause → approve gate → SUCCESS
```

---

## How to Resume (Commands Ready to Run)

```bash
# Step 1 — Release unattached EIPs
aws ec2 release-address --allocation-id eipalloc-0b5ac0f48fbd10850 --region us-east-1
aws ec2 release-address --allocation-id eipalloc-017a31031860a4164 --region us-east-1

# Step 2 — Start Jenkins
aws ec2 start-instances --instance-ids i-0ae539b167d765370 --region us-east-1

# Step 3 — Get new IP
aws ec2 describe-instances --instance-ids i-0ae539b167d765370 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# Step 4 — Full stack redeploy
cd lab-2 && terraform apply -var-file=terraform.tfvars
```

---

## What This Demonstrates (For Study / Interview Context)

This lab proves end-to-end competency in three layers most candidates only understand in isolation:

**Layer 1 — Infrastructure as Code** Terraform managing 116 resources across VPC, EC2, RDS, ALB, WAF, CloudFront, Route53, Secrets Manager, S3, IAM, Lambda — with remote state in S3 and `prevent_destroy` lifecycle guards on critical volumes.

**Layer 2 — Security Architecture** No hardcoded secrets anywhere in the codebase. Credentials injected at runtime via Jenkins credential store. Origin cloaking prevents direct ALB access. WAF enforces rate limits and path rules at both CloudFront and regional layers.

**Layer 3 — CI/CD Pipeline Maturity** Human approval gate on all infrastructure changes — including webhook-triggered ones. Plan artifact archived before approval so the reviewer sees exactly what will happen. Gate tests run post-deploy to validate security posture programmatically, not manually.

> **The economic argument:** Every manual infrastructure change is an undocumented audit event. This pipeline makes every change auditable, reversible, and reviewable — which is the difference between passing a SOC 2 audit and failing one.

---

## What to Study Before Next Session

|Topic|Why It Matters|
|---|---|
|Terraform state management (import, rm, taint)|You used all three in debugging — know why each exists|
|Jenkins declarative pipeline syntax|`when{}`, `withCredentials{}`, `triggers{}` — understand the lifecycle|
|AWS Secrets Manager rotation|The AWSPENDING stuck-version bug you hit is a real production pattern|
|GitHub webhook events + HMAC secrets|Current webhook has no secret — anyone who knows the URL can trigger builds|
|EBS vs instance store|Core reason your Jenkins data was lost — understand the difference|

---

**Repo:** `Class-6-Hungry-Wolves/Class-7-Armageddon` | **Branch:** `nikrdf-armageddon-branch`  
**Jenkins job:** `vandelay-lab2-pipeline` | **Last successful build:** #7 (CLI) and #8 (Webhook, aborted at gate)  
**Stack:** Paused. Code ready. Pipeline proven. Resume when ready.