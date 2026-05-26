# Project 3: Observability + Security Hardening

> **Goal:** Add visibility and defense into the existing architecture. Build the audit,
> monitoring, and threat detection layer that makes production systems safe and debuggable.

---

## What We Built

```
VPC Flow Logs → CloudWatch Log Group → Metric Filter → Alarm → SNS
CloudTrail    → S3 Bucket (encrypted, versioned)
GuardDuty     → findings → EventBridge → SNS
Config        → continuous compliance evaluation → 3 managed rules
```

---

## Architecture Diagram

```
                    ┌─────────────────────────────────┐
                    │          VPC (Lab 1)             │
                    │                                  │
                    │  Every network flow logged       │
                    │         ↓                        │
                    │  VPC Flow Logs                   │
                    └──────────┬──────────────────────-┘
                               │
                    ┌──────────▼──────────┐
                    │  CloudWatch Logs    │
                    │  /aws/vpc/flow-logs │
                    └──────────┬──────────┘
                               │  metric filter (REJECT spike)
                    ┌──────────▼──────────┐
                    │  CloudWatch Alarm   │──→ SNS → Email
                    └─────────────────────┘

Every AWS API call → CloudTrail → S3 (encrypted, log file validation)

GuardDuty (ML threat detection) → EventBridge → SNS → Email

Config recorder → S3 → 3 compliance rules evaluated continuously
```

---

## Design Decisions

**Why VPC Flow Logs go to CloudWatch instead of S3?**
S3 is cheaper for long-term retention but CloudWatch enables metric filters — the ability
to watch log content in real time and trigger alarms on patterns. For operational alerting
(rejected traffic spikes) CloudWatch is the right destination. For long-term forensics,
S3 is better. In production you'd often do both.

**Why `traffic_type = ALL` instead of `REJECT` only?**
Accepted traffic establishes your normal baseline. Without it you can't distinguish
anomalous accepted traffic (unexpected connections to your instances) from normal traffic.
The cost increase is minimal at lab volumes.

**Why is the CloudTrail trail multi-region?**
IAM, STS, and CloudFront always log to `us-east-1` regardless of where you're working.
A single-region trail misses these global service events entirely. Multi-region is always
the correct choice for a real audit trail.

**Why `enable_log_file_validation = true`?**
Generates hourly digest files that allow cryptographic verification that log files weren't
modified or deleted after delivery. Required for compliance scenarios and makes CloudTrail
admissible as an audit artifact.

**Why reuse the CloudTrail bucket for Config?**
Avoids creating another bucket with another policy. Both services deliver logs to S3 and
the bucket policy already allows AWS service writes. In a large production environment
you'd separate them, but for a lab it's clean and cost-effective.

**Why GuardDuty → EventBridge → SNS instead of a CloudWatch alarm?**
GuardDuty doesn't emit CloudWatch metrics — it publishes findings to EventBridge as
structured JSON events. EventBridge rules filter and route those events. The SNS topic
policy must explicitly allow `events.amazonaws.com` to publish, otherwise findings are
generated but silently dropped.

**Config is eventually consistent, not real-time.**
After remediating a non-compliant resource, the compliance dashboard lags behind reality.
Use `start-config-rules-evaluation` to trigger immediate re-evaluation rather than waiting
for the next scheduled sweep. For real-time alerting on compliance changes, combine Config
with an EventBridge rule on `Config Rules Compliance Change` events.

---

## File Structure

```
projects/03-observability/
├── main.tf          # Provider config, S3 backend
├── variables.tf     # Input variables including log retention periods
├── data.tf          # Remote state from Lab 1, aws_caller_identity, aws_region
├── flowlogs.tf      # IAM role, CloudWatch log group, flow log, metric filter, alarm, SNS
├── cloudtrail.tf    # S3 bucket + policy + encryption, CloudTrail trail
├── guardduty.tf     # GuardDuty detector + features, EventBridge rule + target, SNS policy
├── config.tf        # IAM role, Config recorder, delivery channel, recorder status, 3 rules
└── outputs.tf       # CloudTrail ARN, bucket name, flow log group, GuardDuty detector ID
```

---

## Config Rules and Results

| Rule                        | Identifier                                 | Result                        |
| --------------------------- | ------------------------------------------ | ----------------------------- |
| No unrestricted SSH         | `INCOMING_SSH_DISABLED`                    | COMPLIANT ✅                  |
| RDS not publicly accessible | `RDS_INSTANCE_PUBLIC_ACCESS_CHECK`         | COMPLIANT ✅                  |
| S3 public access blocked    | `S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED` | NON_COMPLIANT → remediated ✅ |

The S3 rule found a real finding: `tab-cloud-training-2019`, a bucket from 2019 with no
public access block configured. The bucket was deleted and Config re-evaluated to COMPLIANT.

---

## Key Concepts

### The difference between CloudTrail and Config

- **CloudTrail** records _actions_ — who called what API, when, from where
- **Config** records _state_ — what does the resource look like right now, has it drifted

Both are required for a complete audit and compliance posture.

### Flow Log metric filter pattern

```
[version, account, eni, source, destination, srcport, destport,
 protocol, packets, bytes, windowstart, windowend, action=REJECT, flowlogstatus]
```

The `action=REJECT` condition filters to only rejected connections, incrementing the
`RejectedConnections` metric in the `ArchLab/VPC` custom namespace.

### GuardDuty data sources

GuardDuty automatically analyzes three data sources:

- VPC Flow Logs (network anomalies, port scanning, C2 callbacks)
- CloudTrail (credential abuse, impossible travel, API anomalies)
- DNS logs (domain generation algorithms, data exfiltration)

Additional features enabled: S3 data event protection, EBS malware scanning.

### IAM policy size limit

AWS enforces a 6,144 character limit per IAM policy document. After accumulating
permissions across three labs, the single `lab_ec2_vpc` policy hit this limit.
Resolution: split into three focused policies by domain:

- `lab_networking` — EC2, VPC, ALB, ASG, SSM
- `lab_data` — RDS, ElastiCache, Secrets Manager, S3
- `lab_observability` — CloudWatch, CloudTrail, GuardDuty, Config, SNS, IAM roles

---

## Cost Profile

| Resource        | Cost                | Notes                           |
| --------------- | ------------------- | ------------------------------- |
| VPC Flow Logs   | ~$0.50/GB ingested  | Negligible at lab traffic       |
| CloudTrail      | Free (1 trail)      | S3 storage is cents             |
| GuardDuty       | Free 30-day trial   | ~$1-3/month after trial         |
| Config recorder | ~$0.003/config item | Cents for a lab                 |
| CloudWatch Logs | ~$0.50/GB ingested  | 14-day retention keeps cost low |

**Nothing in Lab 3 needs session script management** — all resources are either free
or cheap enough to leave running permanently.

---

## Lessons Learned

**Config found a real security issue on day one.**
The S3 public access rule immediately flagged `tab-cloud-training-2019`, a forgotten
2019 bucket with no public access block. This is Config doing exactly what it's designed
for — surfacing drift from security best practices regardless of when it was introduced.

**GuardDuty's `datasources` block is deprecated.**
Use `aws_guardduty_detector_feature` resources instead. The old inline `datasources`
block still works but produces deprecation warnings. Feature names: `S3_DATA_EVENTS`,
`EBS_MALWARE_PROTECTION`, `RUNTIME_MONITORING`, etc.

**The SNS topic policy is easy to miss.**
EventBridge needs explicit `sns:Publish` permission to forward GuardDuty findings to
SNS. Without `aws_sns_topic_policy` the EventBridge rule is created but findings are
silently dropped — no error, just no notifications.

**`aws_cloudwatch_event_rule` is the current resource name for EventBridge.**
Despite AWS renaming CloudWatch Events to EventBridge, the Terraform resource is still
`aws_cloudwatch_event_rule` and `aws_cloudwatch_event_target`. Don't let the naming
inconsistency confuse you.

**Config's initialization order must be explicit.**
Recorder → delivery channel → recorder status → rules. The `depends_on` chain is
required because Terraform can't always infer this ordering from implicit references.

**`data.aws_region.current.name` is deprecated.**
Use `data.aws_region.current.region` instead. Small change, same value.

---

## Useful Commands

```bash
# Check Config compliance across all rules
aws configservice describe-compliance-by-config-rule \
  --query "ComplianceByConfigRules[*].{Rule:ConfigRuleName,Compliance:Compliance.ComplianceType}" \
  --output table

# Find which specific resources are non-compliant for a rule
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name <rule-name> \
  --compliance-types NON_COMPLIANT \
  --query "EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId}" \
  --output table

# Force immediate re-evaluation after remediation
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>

# Check GuardDuty detector status
aws guardduty list-detectors

# View recent CloudTrail events by service
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=s3.amazonaws.com \
  --max-results 10 \
  --query "Events[*].{Time:EventTime,User:Username,Event:EventName}" \
  --output table
```

---

## What You Can Say in an Interview

> "I built a full observability and security layer on top of a multi-AZ VPC architecture.
> VPC Flow Logs feed into CloudWatch with metric filters that alarm on rejected traffic
> spikes. CloudTrail captures every API call with log file validation for integrity.
> GuardDuty does continuous ML-based threat detection across flow logs, CloudTrail,
> and DNS. AWS Config runs three compliance rules continuously — and on day one it found
> a real security gap: a forgotten S3 bucket from 2019 with no public access block.
> I remediated it immediately. Everything is Terraform."
