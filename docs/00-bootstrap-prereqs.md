# Bootstrap Prerequisites

> What to do before running Terraform for the first time

---

## The Chicken-and-Egg Problem

Terraform needs AWS credentials to run. But we use Terraform to create the scoped IAM user
that will hold those credentials. There is no way around this: **one manual step is required
before any Terraform can be applied.**

This is normal and expected. Every AWS account bootstrap has this same constraint.

---

## Step 1 — Manual Setup (do this once)

> ⚠️ These steps are performed in the AWS Console or via the root user. They cannot be
> Terraformed because Terraform has no credentials yet.

1. Log into the AWS Console as root
2. Go to **IAM → Users → Create user**
3. Name it something like `bootstrap-admin`
4. Attach `AdministratorAccess` — this is temporary and will be deleted
5. Create an access key for programmatic access
6. Set the credentials in your environment:

```bash
export AWS_ACCESS_KEY_ID=<access_key>
export AWS_SECRET_ACCESS_KEY=<secret_key>
export AWS_DEFAULT_REGION=us-east-1
```

Verify the identity before continuing:

```bash
aws sts get-caller-identity
```

You should see the `bootstrap-admin` user ARN in the output. If you see root, stop — do not
proceed with root credentials.

---

## Step 2 — Run the Bootstrap Terraform

With bootstrap credentials in your environment, run the bootstrap module. This creates:

- S3 bucket for Terraform remote state
- DynamoDB table for state locking
- Scoped IAM user (`aws-arch-lab-deployer`) with only the permissions labs require

```bash
cd bootstrap/
terraform init
terraform plan
terraform apply
```

---

## Step 3 — Migrate to Scoped Credentials

1. Generate an access key for `aws-arch-lab-deployer` (console or CLI)

```bash
aws iam create-access-key --user-name aws-arch-lab-deployer
```

2. Add a new profile to `~/.aws/credentials`:

```ini
[aws-arch-lab-deployer]
aws_access_key_id = <deployer_access_key>
aws_secret_access_key = <deployer_secret_key>
```

3. Switch your environment to the scoped profile:

```bash
export AWS_PROFILE=aws-arch-lab-deployer
```

4. Delete the `bootstrap-admin` user from the console — it has served its purpose
5. Migrate Terraform state to the S3 backend by adding the backend block to
   `bootstrap/main.tf` and re-running `terraform init`

```bash
  backend "s3" {
    bucket         = "aws-arch-lab-tfstate"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true
  }
```

---

## Credential Hierarchy Going Forward

| Identity                | Role                      | Usage                              |
| ----------------------- | ------------------------- | ---------------------------------- |
| `root`                  | MFA only, no access keys  | Never used for CLI                 |
| `bootstrap-admin`       | Break-glass, admin access | Use only if deployer is locked out |
| `aws-arch-lab-deployer` | Scoped permissions        | Daily driver for all lab Terraform |

> ⚠️ **Never commit credentials to git.** The `.gitignore` at the repo root excludes `.env`
> and `credentials` files. AWS credentials live only in `~/.aws/` or environment variables.
