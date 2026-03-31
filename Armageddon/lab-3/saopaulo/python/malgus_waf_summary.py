#!/usr/bin/env python3
import boto3, time, json, argparse
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# He enjoys watching attacks get denied at the edge—statistics are trophies.
# Reason why this script is relevant to your career.
# WAF analysis and false-positive detection are daily security operations.
# How you would talk about this script at an interview.
# "I standardized WAF triage by querying logs and producing an audit-friendly summary."


def run(logs_client, group, query, minutes):
    end = int(datetime.now(timezone.utc).timestamp())
    start = int((datetime.now(timezone.utc) - timedelta(minutes=minutes)).timestamp())
    qid = logs_client.start_query(
        logGroupName=group, startTime=start, endTime=end,
        queryString=query, limit=50
    )["queryId"]
    for _ in range(30):
        r = logs_client.get_query_results(queryId=qid)
        if r["status"] == "Complete":
            return [{x["field"]: x["value"] for x in row} for row in r["results"]]
        time.sleep(1)
    raise TimeoutError("Query timed out")


def main():
    ap = argparse.ArgumentParser(description="WAF log summary from CloudWatch Logs Insights")
    ap.add_argument("--log-group", required=True, help="CloudWatch log group name (e.g. aws-waf-logs-liberdade-sp-webacl)")
    ap.add_argument("--region", default="sa-east-1", help="AWS region (default: sa-east-1)")
    ap.add_argument("--minutes", type=int, default=120, help="Lookback window in minutes (default: 120)")
    args = ap.parse_args()

    logs_client = boto3.client("logs", region_name=args.region)

    print(f"WAF Summary — {args.log_group} ({args.region})")
    print(f"Window: last {args.minutes} minutes")
    print("=" * 60)

    actions = run(logs_client, args.log_group,
                  "stats count(*) as hits by action | sort hits desc", args.minutes)
    top_ips = run(logs_client, args.log_group,
                  "stats count(*) as hits by httpRequest.clientIp as ip | sort hits desc | limit 10", args.minutes)
    top_uris = run(logs_client, args.log_group,
                   "stats count(*) as hits by httpRequest.uri as uri | sort hits desc | limit 10", args.minutes)
    top_countries = run(logs_client, args.log_group,
                        "stats count(*) as hits by httpRequest.country as country | sort hits desc | limit 10", args.minutes)
    blocked_rules = run(logs_client, args.log_group,
                        "filter action = 'BLOCK' | stats count(*) as hits by terminatingRuleId as rule | sort hits desc | limit 10",
                        args.minutes)

    result = {
        "log_group": args.log_group,
        "region": args.region,
        "window_minutes": args.minutes,
        "actions": actions,
        "top_ips": top_ips,
        "top_uris": top_uris,
        "top_countries": top_countries,
        "blocked_rules": blocked_rules,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
