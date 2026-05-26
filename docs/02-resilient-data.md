# Project 2: Resilient Data Layer

> **Goal:** Add a production-grade stateful data layer to the Lab 1 architecture. Understand RDS Multi-AZ failover, ElastiCache Redis, and credential management via Secrets Manager.

---

## What We Built

```
Internet
    ↓
ALB (public subnets, us-east-1a + us-east-1b)
    ↓
EC2 (private subnets)
    ↓                    ↓
RDS MySQL            ElastiCache Redis
Multi-AZ             Single node
(primary + standby)  cache.t3.micro
db.t3.micro

Secrets Manager — DB credentials, never in code or state
```

---

## Architecture Diagram

```
              ┌─────────────────────────────────┐
              │          VPC (Lab 1)             │
              │         10.0.0.0/16              │
              │                                  │
              │  ┌──────────────────────────┐    │
              │  │      Private Subnets      │    │
              │  │   AZ-a        AZ-b        │    │
              │  │                           │    │
              │  │   EC2    ←→   EC2         │    │
              │  │    ↓               ↓      │    │
              │  │  RDS           RDS        │    │
              │  │ Primary       Standby     │    │
              │  │ (us-east-1b) (us-east-1a) │    │
              │  │                           │    │
              │  │  ElastiCache Redis        │    │
              │  │  (us-east-1b)             │    │
              │  └──────────────────────────┘    │
              └─────────────────────────────────-┘
```

---

## Design Decisions

**Why RDS Multi-AZ instead of a single instance?**
A single RDS instance is a single point of failure. Multi-AZ provisions a synchronous standby in a second AZ. If the primary fails, AWS automatically promotes the standby in ~60 seconds with zero data loss. The application endpoint DNS name stays the same — no config changes required on the app side.

**Why Multi-AZ is not the same as Read Replicas:**
This is one of the most tested distinctions on the SAA-C03:

- **Multi-AZ** = synchronous standby for HA and automatic failover. The standby is not readable.
- **Read Replicas** = asynchronous copies for read scaling. Not automatic failover targets.

Use Multi-AZ for availability. Use Read Replicas for performance.

**Why Secrets Manager instead of a Terraform variable?**
Passwords in variables end up in state files, plan output, and potentially git history — all in plaintext. Secrets Manager generates the password, stores it encrypted, and the application retrieves it at runtime via the AWS SDK. Terraform never exposes the plaintext value.

**Why `recovery_window_in_days = 0` on the secret?**
By default Secrets Manager holds deleted secrets for 30 days before permanently removing them. During that window the name is reserved — recreating a secret with the same name fails. For lab teardown/rebuild cycles, immediate deletion is required.

**Why Redis over Memcached?**

- Redis supports persistence, data structures, pub/sub, and replication
- Memcached is pure cache, multi-threaded, simpler
- Redis is what production systems use for session storage and query caching
- Use Memcached only when you need pure throwaway cache and multi-threading matters

**Why `aws_elasticache_cluster` instead of `aws_elasticache_replication_group`?**
`aws_elasticache_cluster` = single node or Memcached clusters. Simple, cheap for labs.
`aws_elasticache_replication_group` = Redis with primary + replica across AZs, automatic failover. Use this in production for HA Redis.

**Why CIDR-based security group rules instead of SG chaining for RDS/Redis?**
Lab 1's EC2 security group lives in a different Terraform project. Cross-project SG references require exporting the SG ID as an output and importing it via remote state. Using the private subnet CIDRs is simpler for this lab and still restricts access to only instances within the private subnets. In a single-project architecture, SG chaining is always preferred.

---

## File Structure

```
projects/02-resilient-data/
├── main.tf           # Provider config, S3 backend
├── variables.tf      # Input variables — no passwords
├── data.tf           # Remote state reference to Lab 1 VPC outputs
├── secrets.tf        # Random password generation, Secrets Manager secret + version
├── rds.tf            # DB subnet group, RDS security group, RDS MySQL Multi-AZ instance
├── elasticache.tf    # Cache subnet group, Redis security group, ElastiCache cluster
└── outputs.tf        # RDS endpoint, Redis endpoint, secret ARN
```

---

## Key Concepts

### Remote State References

Lab 2 reads VPC IDs and subnet IDs directly from Lab 1's Terraform state:

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/01-vpc-foundation/terraform.tfstate"
    region = "us-east-1"
  }
}
```

This avoids hardcoding IDs and means Lab 2 automatically picks up changes if Lab 1 is rebuilt. Only values declared as `output` blocks in Lab 1 are accessible this way.

### RDS Failover

Triggered manually for testing:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier arch-lab-02-mysql \
  --force-failover
```

Confirmed via event log:

```bash
aws rds describe-events \
  --source-identifier arch-lab-02-mysql \
  --source-type db-instance \
  --query "Events[*].{Time:Date,Message:Message}" \
  --output table
```

**Observed failover time: ~45 seconds.** The AZ flipped from `us-east-1b` to `us-east-1a`. The endpoint DNS name did not change.

---

## Cost Profile

| Resource                   | Cost                    | Notes                                   |
| -------------------------- | ----------------------- | --------------------------------------- |
| RDS db.t3.micro Multi-AZ   | ~$0.023/hr              | Biggest cost — destroy between sessions |
| ElastiCache cache.t3.micro | ~$0.017/hr              | Destroy between sessions                |
| Secrets Manager            | ~$0.40/month per secret | Negligible                              |

**Session script manages teardown automatically:**

```bash
./scripts/session.sh down   # destroys RDS + ElastiCache
./scripts/session.sh up     # recreates RDS + ElastiCache
```

---

## Lessons Learned

**RDS Multi-AZ failover doesn't always show AZ flip in real time.**
The `AvailabilityZone` field in `describe-db-instances` may not update until the new primary is fully available. The event log via `describe-events` is the authoritative source — look for `Multi-AZ instance failover completed`.

**Service-linked role permission is required for RDS.**
The first time RDS is used in an account it needs to create a service-linked IAM role. The deployer user needs `iam:CreateServiceLinkedRole` — without it RDS creation fails with `InvalidParameterValue: Unable to create the resource. Verify that you have permission to create service linked role`. This role persists permanently once created.

**Secrets Manager `recovery_window_in_days` defaults to 30.**
Deleting a secret and immediately recreating it with the same name fails because the name is reserved during the recovery window. Always set `recovery_window_in_days = 0` for lab secrets.

**`bash -c 'echo >/dev/tcp/host/port'` is the most portable connectivity test.**
Neither `telnet` nor `nc` are guaranteed to be available on AL2023. Bash's built-in `/dev/tcp` pseudo-device works everywhere bash is installed — no packages required.

**`-target` warnings from Terraform are expected for session management.**
Using `terraform destroy -target=...` always produces a warning that the plan may be incomplete. This is informational — it's reminding you that only targeted resources were evaluated. For intentional partial destroys (like session management) this is correct behavior.

---

## Connectivity Verification

From an EC2 instance via SSM Session Manager:

```bash
# Test RDS connectivity
bash -c 'echo >/dev/tcp/<rds-endpoint>/3306' && echo "RDS: connected" || echo "RDS: failed"

# Test Redis connectivity
bash -c 'echo >/dev/tcp/<redis-endpoint>/6379' && echo "Redis: connected" || echo "Redis: failed"
```

Both returned `connected` confirming security groups and routing are correct.

---

## What You Can Say in an Interview

> "I built a multi-AZ data layer on top of a custom VPC — RDS MySQL with a synchronous
> standby in a second AZ, ElastiCache Redis for session and query caching, and Secrets
> Manager for credential management so passwords never appear in code or state files.
> I tested Multi-AZ failover hands-on — the standby promoted in under 60 seconds with
> zero data loss, and the application endpoint stayed the same throughout. Everything
> is Terraform with targeted destroy so I can stop the cost clock between sessions."
