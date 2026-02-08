#!/usr/bin/env python3
import boto3, json
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# Malgus doesn't ask "what changed?" — he interrogates the timeline until it confesses.
# Reason why this script is relevant to your career.
# Change attribution is core to incident response and audit defense.
# How you would talk about this script at an interview.
# "I automated change tracking by querying CloudTrail for security/network/CDN modifications."

# Lab-relevant services — filters out STS, KMS, IAM noise
RELEVANT_SOURCES = {
    "ec2.amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "rds.amazonaws.com",
    "wafv2.amazonaws.com",
    "cloudfront.amazonaws.com",
    "route53.amazonaws.com",
    "secretsmanager.amazonaws.com",
    "monitoring.amazonaws.com",
    "sns.amazonaws.com",
    "s3.amazonaws.com",
}

# Read-only prefixes that clutter the timeline
SKIP_READONLY = ("Describe", "List", "Get", "Head", "Lookup", "Check", "Decode")

def lookup(region, minutes=120):
    ct = boto3.client("cloudtrail", region_name=region)
    end = datetime.now(timezone.utc)
    start = end - timedelta(minutes=minutes)

    resp = ct.lookup_events(StartTime=start, EndTime=end, MaxResults=50)
    events = []
    for e in resp.get("Events", []):
        source = e.get("EventSource", "")
        name = e.get("EventName", "")

        if source not in RELEVANT_SOURCES:
            continue
        if name.startswith(SKIP_READONLY):
            continue

        resources = [
            {"type": r.get("ResourceType", ""), "name": r.get("ResourceName", "")}
            for r in e.get("Resources", [])
        ]

        events.append({
            "region": region,
            "time": str(e.get("EventTime")),
            "event": name,
            "user": e.get("Username"),
            "source": source.split(".")[0],
            "resources": resources,
            "error": e.get("ErrorCode"),
        })
    return events

def main():
    tokyo = lookup("ap-northeast-1")
    sp    = lookup("sa-east-1")
    print(json.dumps({"tokyo": tokyo, "saopaulo": sp}, indent=2))

if __name__ == "__main__":
    main()
