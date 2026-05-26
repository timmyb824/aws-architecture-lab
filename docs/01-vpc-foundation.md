# Project 1: VPC + Compute Foundation

> **Goal:** Stop using default VPCs forever. Understand subnets, routing, and IAM from scratch.

---

## What We Built

```
Internet
    ↓
ALB (public subnets, us-east-1a + us-east-1b)
    ↓  security group chaining — EC2 only accepts traffic from ALB
2x EC2 (private subnets, no public IPs, no SSH)
    ↓  outbound via NAT Gateway
Internet (package installs, SSM endpoints)

SSM Session Manager — shell access with zero open ports
CloudWatch Alarms  — CPU, 5xx errors, latency, unhealthy hosts
SNS Topic          — notification target for all alarms
```

---

## Architecture Diagram

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │     IGW     │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │          VPC            │
              │      10.0.0.0/16        │
              │                         │
              │  ┌─────────────────┐    │
              │  │  Public Subnets │    │
              │  │  AZ-a  │  AZ-b  │    │
              │  │  ALB   │  ALB   │    │
              │  │  NAT   │        │    │
              │  └────────┬────────┘    │
              │           │             │
              │  ┌────────┴────────┐    │
              │  │ Private Subnets │    │
              │  │  AZ-a  │  AZ-b  │    │
              │  │  EC2   │  EC2   │    │
              │  └─────────────────┘    │
              └─────────────────────────┘
```

---

## Design Decisions

**Why two AZs?**
Every production AWS architecture spans at least two AZs. If one data center goes down your app stays up. The ALB requires multiple AZs to even function. This is the default posture — single AZ is the exception, not the rule.

**Why public/private subnet split?**
EC2 instances have no business being reachable from the internet directly. They only need to serve traffic from the ALB, which sits in the public subnet. The private subnet has no inbound route from the internet — only outbound via NAT for things like package installs. This contains blast radius if an instance is compromised.

**Why SSM over a bastion host?**
A bastion host is an EC2 instance in the public subnet you SSH into, then hop to private instances. It works but it's a thing to patch, a security group to maintain, and a key to manage. SSM Session Manager lets you shell into any instance with zero open ports and zero SSH keys — AWS handles auth via IAM. It's strictly better and what modern teams use.

**Why NAT Gateway only when needed?**
NAT Gateway costs ~$0.045/hr plus data transfer — ~$32/month if left running. For a lab where you're not actively using it, that's waste. `nat.tf` is intentionally isolated so the NAT Gateway can be destroyed and recreated independently without touching the rest of the infrastructure.

```bash
# Destroy between sessions
terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat

# Recreate next session
terraform apply -target=aws_nat_gateway.main -target=aws_eip.nat
```

**Why security group chaining instead of CIDR rules on EC2?**
The EC2 security group's inbound rule references the ALB security group ID as the source — not a CIDR block. This means only traffic that actually came through the ALB can reach the instances. Even if someone knew an instance's private IP they couldn't reach it directly.

**Why IAM instance profiles instead of access keys?**
Instance profiles attach an IAM role directly to EC2 instances. The instance gets temporary, auto-rotating credentials via the instance metadata service (`169.254.169.254`). No keys on disk, no rotation to manage, no credentials to leak.

---

## File Structure

```
projects/01-vpc-foundation/
├── main.tf         # Provider config, S3 backend
├── variables.tf    # All input variables with defaults
├── vpc.tf          # VPC, subnets, IGW, route tables, associations
├── nat.tf          # NAT Gateway + EIP — isolated for easy destroy/recreate
├── iam.tf          # EC2 instance role, SSM policy attachment, instance profile
├── compute.tf      # Security groups, launch template, ASG, ALB, target group, listener
├── alarms.tf       # SNS topic, CloudWatch alarms (CPU, 5xx, latency, unhealthy hosts)
└── outputs.tf      # ALB DNS name, VPC ID, subnet IDs
```

---

## Subnet CIDR Layout

| Subnet             | CIDR         | AZ         | Tier    |
| ------------------ | ------------ | ---------- | ------- |
| public-us-east-1a  | 10.0.1.0/24  | us-east-1a | Public  |
| public-us-east-1b  | 10.0.2.0/24  | us-east-1b | Public  |
| private-us-east-1a | 10.0.10.0/24 | us-east-1a | Private |
| private-us-east-1b | 10.0.11.0/24 | us-east-1b | Private |

The gap between `10.0.2.x` and `10.0.10.x` is intentional — leaves room for future subnet tiers (e.g. `10.0.20.0/24` for database subnets) without renumbering.

---

## Cost Profile

| Resource             | Cost                 | Notes                      |
| -------------------- | -------------------- | -------------------------- |
| NAT Gateway          | ~$0.045/hr (~$32/mo) | Destroy between sessions   |
| ALB                  | ~$0.008/hr + LCU     | Cheap at low traffic       |
| EC2 t3.micro x2      | ~$0.0104/hr each     | Free tier eligible         |
| EIP (when attached)  | Free                 | Charged only if unattached |
| CloudWatch Alarms x4 | ~$0.40/mo            | Negligible                 |

**Estimated session cost:** $5–15 depending on how long NAT Gateway runs.

---

## Lessons Learned

**Amazon Linux 2023 does not pre-start SSM agent.**
AL2023 ships with the SSM agent binary but the service is not enabled by default. User data must explicitly install, enable, and start it:

```bash
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
```

Without this, instances never register with SSM and `start-session` returns `TargetNotConnected`.

**Least-privilege IAM policies are built incrementally.**
Starting with a scoped deployer user means Terraform hits `403` errors as it discovers APIs it needs. This is expected and correct — each error reveals exactly which permission to add. The final policy accurately reflects what the deployer actually needs, nothing more.

**User data is launch-time only.**
Updating the launch template does not affect running instances. To apply user data changes you must terminate existing instances and let the ASG replace them. This is intentional — instances are disposable, not modified in place.

**Planfiles go stale after partial applies.**
If an apply fails mid-run, don't reuse the planfile. Run a fresh `terraform plan` — Terraform will reconcile what exists against the desired state and produce an accurate diff.

**The `dynamodb_table` backend parameter is deprecated.**
As of AWS provider v6, use `use_lockfile = true` in the S3 backend instead. The DynamoDB lock table is no longer needed.

---

## What You Can Say in an Interview

> "I designed and built a multi-AZ VPC from scratch with public/private subnet separation,
> an internet-facing ALB routing to EC2 instances in private subnets, NAT Gateway for
> outbound-only access, IAM instance profiles for credential-free AWS access, SSM Session
> Manager for shell access with zero open ports, and CloudWatch alarms on the key health
> signals. Everything is Terraform — I can tear it down and rebuild it in under 10 minutes."
