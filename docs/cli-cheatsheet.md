# AWS CLI Cheatsheet

> Commands used across the lab sessions. All assume `AWS_PROFILE` is set appropriately.

---

## Identity & Auth

```bash
# Check which identity you're currently using
aws sts get-caller-identity

# Switch profiles (if not using awsp)
export AWS_PROFILE=aws-arch-lab-deployer

# List policies attached directly to a user
aws iam list-attached-user-policies --user-name <username>

# List inline policies on a user
aws iam list-user-policies --user-name <username>

# List groups a user belongs to
aws iam list-groups-for-user --user-name <username>

# List policies attached to a group
aws iam list-attached-group-policies --group-name <group-name>

# Generate access key for a user
aws iam create-access-key --user-name <username>
```

---

## EC2

```bash
# List instances with state, AZ, and launch time — filtered by project tag
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=arch-lab-01" \
  --query "Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,LaunchTime:LaunchTime,AZ:Placement.AvailabilityZone}" \
  --output table

# List only running instances and get just their IDs
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=arch-lab-01" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text

# Terminate one or more instances
aws ec2 terminate-instances --instance-ids <id1> <id2>

# Decode user data on a running instance (verify what script was attached)
aws ec2 describe-instance-attribute \
  --instance-id <instance-id> \
  --attribute userData \
  --query "UserData.Value" \
  --output text | base64 --decode

# Get boot/console log — useful for debugging user data failures
aws ec2 get-console-output \
  --instance-id <instance-id> \
  --output text
```

---

## NAT Gateway

```bash
# Check NAT Gateway state
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Project,Values=arch-lab-01" \
  --query "NatGateways[*].{ID:NatGatewayId,State:State}" \
  --output table

# Destroy NAT Gateway between sessions to stop cost (from project dir)
terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat

# Recreate NAT Gateway for next session
terraform apply -target=aws_nat_gateway.main -target=aws_eip.nat
```

---

## Auto Scaling

```bash
# Check ASG desired/min/max and current instance states
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names arch-lab-01-asg \
  --query "AutoScalingGroups[*].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}}" \
  --output json

# View scaling activity history
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name arch-lab-01-asg \
  --query "Activities[*].{Status:StatusCode,Description:Description,Time:StartTime}" \
  --output table
```

---

## SSM Session Manager

```bash
# Check which instances are registered and reachable via SSM
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].{ID:InstanceId,Ping:PingStatus,Version:AgentVersion}" \
  --output table

# Start an interactive shell session on an instance (no SSH needed)
aws ssm start-session --target <instance-id>

# Once inside an instance — useful diagnostics
hostname -f                                                               # confirm which instance
curl http://169.254.169.254/latest/meta-data/local-ipv4                  # private IP
curl http://169.254.169.254/latest/meta-data/placement/availability-zone # which AZ
curl -s https://checkip.amazonaws.com                                     # confirms outbound via NAT
systemctl status nginx                                                    # check nginx
systemctl status amazon-ssm-agent                                        # check SSM agent

# Connectivity test — works without telnet or nc
bash -c 'echo >/dev/tcp/<host>/<port>' && echo "connected" || echo "failed"

# Examples
bash -c 'echo >/dev/tcp/<rds-endpoint>/3306' && echo "RDS: connected" || echo "RDS: failed"
bash -c 'echo >/dev/tcp/<redis-endpoint>/6379' && echo "Redis: connected" || echo "Redis: failed"
```

---

## RDS

```bash
# Check RDS instance status, AZ, endpoint, and Multi-AZ flag
aws rds describe-db-instances \
  --db-instance-identifier arch-lab-02-mysql \
  --query "DBInstances[*].{Status:DBInstanceStatus,MultiAZ:MultiAZ,AZ:AvailabilityZone,Endpoint:Endpoint.Address}" \
  --output table

# Trigger a forced Multi-AZ failover (promotes standby to primary)
aws rds reboot-db-instance \
  --db-instance-identifier arch-lab-02-mysql \
  --force-failover

# Watch failover progress in a loop (Ctrl+C to stop)
while true; do
  clear
  aws rds describe-db-instances \
    --db-instance-identifier arch-lab-02-mysql \
    --query "DBInstances[*].{Status:DBInstanceStatus,AZ:AvailabilityZone}" \
    --output table
  sleep 5
done

# View RDS event log — confirm failover happened, check for errors
aws rds describe-events \
  --source-identifier arch-lab-02-mysql \
  --source-type db-instance \
  --query "Events[*].{Time:Date,Message:Message}" \
  --output table
```

---

## ElastiCache

```bash
# Check ElastiCache cluster status
aws elasticache describe-cache-clusters \
  --query "CacheClusters[*].{Status:CacheClusterStatus,Engine:Engine,NodeType:CacheNodeType}" \
  --output table
```

---

## Secrets Manager

```bash
# List secrets in the account
aws secretsmanager list-secrets \
  --query "SecretList[*].{Name:Name,ARN:ARN}" \
  --output table

# Retrieve a secret value (returns JSON with username, password, etc.)
aws secretsmanager get-secret-value \
  --secret-id arch-lab-02/db/credentials \
  --query "SecretString" \
  --output text

# Delete a secret immediately (no recovery window)
aws secretsmanager delete-secret \
  --secret-id <secret-id> \
  --force-delete-without-recovery
```

---

## VPC Flow Logs & CloudWatch

```bash
# Check flow log status
aws ec2 describe-flow-logs \
  --filter "Name=tag:Project,Values=arch-lab-03" \
  --query "FlowLogs[*].{ID:FlowLogId,Status:FlowLogStatus,Destination:LogDestination}" \
  --output table

# View recent flow log entries (from CloudWatch Logs Insights console is easier)
# Or use the CLI to get log streams
aws logs describe-log-streams \
  --log-group-name /aws/vpc/flow-logs/arch-lab-03 \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  --query "logStreams[*].{Stream:logStreamName,LastEvent:lastEventTime}" \
  --output table
```

---

## CloudTrail

```bash
# View recent API calls by service
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=s3.amazonaws.com \
  --max-results 10 \
  --query "Events[*].{Time:EventTime,User:Username,Event:EventName}" \
  --output table

# View recent RDS API calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=rds.amazonaws.com \
  --max-results 10 \
  --query "Events[*].{Time:EventTime,User:Username,Event:EventName}" \
  --output table

# Look up events by a specific user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=aws-arch-lab-deployer \
  --max-results 10 \
  --query "Events[*].{Time:EventTime,Event:EventName,Source:EventSource}" \
  --output table
```

---

## GuardDuty

```bash
# List GuardDuty detectors
aws guardduty list-detectors

# Get detector details including enabled features
aws guardduty get-detector \
  --detector-id <detector-id>

# List findings (if any)
aws guardduty list-findings \
  --detector-id <detector-id>
```

---

## AWS Config

```bash
# Check compliance status across all rules
aws configservice describe-compliance-by-config-rule \
  --query "ComplianceByConfigRules[*].{Rule:ConfigRuleName,Compliance:Compliance.ComplianceType}" \
  --output table

# Find which specific resources are non-compliant for a rule
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name <rule-name> \
  --compliance-types NON_COMPLIANT \
  --query "EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Type:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceType}" \
  --output table

# Force immediate re-evaluation after remediating a resource
aws configservice start-config-rules-evaluation \
  --config-rule-names <rule-name>

# Check Config recorder status
aws configservice describe-configuration-recorder-status \
  --query "ConfigurationRecordersStatus[*].{Name:name,Recording:recording,LastStatus:lastStatus}" \
  --output table
```

---

## S3 (State Bucket)

```bash
# Verify state files exist in the bucket
aws s3 ls s3://aws-arch-lab-tfstate/bootstrap/
aws s3 ls s3://aws-arch-lab-tfstate/projects/01-vpc-foundation/
aws s3 ls s3://aws-arch-lab-tfstate/projects/02-resilient-data/
aws s3 ls s3://aws-arch-lab-tfstate/projects/03-observability/
aws s3 ls s3://aws-arch-lab-tfstate/projects/04-full-architecture/

# List all objects in a bucket
aws s3 ls s3://<bucket-name> --recursive

# Delete a bucket and all its contents
aws s3 rb s3://<bucket-name> --force
```

---

## SNS

```bash
# Subscribe an email to an SNS topic
aws sns subscribe \
  --topic-arn <topic-arn> \
  --protocol email \
  --notification-endpoint your@email.com

# List subscriptions on a topic (check confirmation status)
aws sns list-subscriptions-by-topic \
  --topic-arn <topic-arn>

# Delete a subscription (e.g. wrong email, pending confirmation)
aws sns unsubscribe \
  --subscription-arn <subscription-arn>
```

---

## Route Tables

```bash
# Verify private subnet route table has NAT Gateway route
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=arch-lab-01-rt-private" \
  --query "RouteTables[*].Routes" \
  --output table
```

---

## CloudFront

```bash
# List distributions and their status
aws cloudfront list-distributions \
  --query "DistributionList.Items[*].{ID:Id,Domain:DomainName,Status:Status,Aliases:Aliases.Items}" \
  --output table

# Get distribution details by ID
aws cloudfront get-distribution \
  --id <distribution-id> \
  --query "Distribution.{Status:Status,Domain:DomainName,WAF:WebACLId}" \
  --output table

# Invalidate cached content (forces CloudFront to fetch fresh from origin)
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"

# Check invalidation status
aws cloudfront list-invalidations \
  --distribution-id <distribution-id> \
  --query "InvalidationList.Items[*].{ID:Id,Status:Status,CreateTime:CreateTime}" \
  --output table
```

---

## Route 53

```bash
# List hosted zones
aws route53 list-hosted-zones \
  --query "HostedZones[*].{Name:Name,ID:Id,Records:ResourceRecordSetCount}" \
  --output table

# List records in a zone
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[*].{Name:Name,Type:Type,TTL:TTL}" \
  --output table

# Check health check status
aws route53 get-health-check-status \
  --health-check-id <health-check-id> \
  --query "HealthCheckObservations[*].{Region:Region,Status:StatusReport.Status}" \
  --output table

# Get NS records for a zone (needed for delegation)
aws route53 get-hosted-zone \
  --id <zone-id> \
  --query "DelegationSet.NameServers" \
  --output table
```

---

## WAF

```bash
# List Web ACLs (CloudFront WAFs are always in us-east-1)
aws wafv2 list-web-acls \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --query "WebACLs[*].{Name:Name,ID:Id,ARN:ARN}" \
  --output table

# Get Web ACL details including rules
aws wafv2 get-web-acl \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --name arch-lab-04-waf \
  --id <web-acl-id>

# Get WAF metrics from CloudWatch (blocked requests)
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=arch-lab-04-waf Name=Region,Value=us-east-1 \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table
```

---

## Terraform Quick Reference

```bash
# Standard workflow
terraform init
terraform plan -out planfile
terraform apply planfile

# Apply without a planfile (prompts for yes)
terraform apply

# Apply without prompt — use carefully
terraform apply --auto-approve

# Destroy specific resources without touching the rest
terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat

# Destroy everything in the project
terraform destroy

# Show what Terraform knows about a specific resource
terraform state show <resource_type>.<resource_name>

# List all resources Terraform is tracking
terraform state list

# Pull current outputs
terraform output
```

---

## Session Management

```bash
# End of day — stop the cost clock
export AWS_PROFILE=aws-arch-lab-deployer
./scripts/session.sh down

# Start of day — bring expensive resources back up
export AWS_PROFILE=aws-arch-lab-deployer
./scripts/session.sh up
```

---

## Profile Reference

| Profile                 | Identity                         | When to use                                 |
| ----------------------- | -------------------------------- | ------------------------------------------- |
| `default`               | `bootstrap-admin` (AdminAccess)  | Bootstrap only — IAM, account-level changes |
| `aws-arch-lab-deployer` | `aws-arch-lab-deployer` (scoped) | All lab project Terraform                   |
| root                    | MFA console only                 | Break-glass only, never CLI                 |
