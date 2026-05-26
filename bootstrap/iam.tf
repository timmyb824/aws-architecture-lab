resource "aws_iam_user" "terraform_deployer" {
  name = "${var.project_name}-deployer"

  tags = {
    Project = var.project_name
  }
}

# Scoped policy — only what Terraform needs for state management
# We'll expand this as labs require more permissions
resource "aws_iam_policy" "terraform_state_access" {
  name        = "${var.project_name}-tfstate-access"
  description = "Allows Terraform to read/write state in S3 and lock in DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "terraform_deployer" {
  user       = aws_iam_user.terraform_deployer.name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

# -----------------------------------------------------------------------------
# Policy 1 — Networking (VPC, EC2, NAT, SG, ALB, ASG)
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "lab_networking" {
  name        = "${var.project_name}-lab-networking"
  description = "VPC, EC2, ALB, ASG permissions for labs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs",
          "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets",
          "ec2:ModifySubnetAttribute", "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
          "ec2:DescribeRouteTables", "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:DescribeNatGateways", "ec2:AllocateAddress",
          "ec2:ReleaseAddress", "ec2:DescribeAddresses",
          "ec2:DescribeAddressesAttribute", "ec2:AssociateAddress",
          "ec2:DisassociateAddress", "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus", "ec2:StopInstances", "ec2:StartInstances",
          "ec2:DescribeImages", "ec2:DescribeKeyPairs",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags",
          "ec2:CreateTags", "ec2:DeleteTags", "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate", "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions", "ec2:CreateLaunchTemplateVersion",
          "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs", "ec2:DescribeFlowLogs",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:CreateOrUpdateTags",
          "autoscaling:DescribeTags",
          "ssm:GetParameter", "ssm:DescribeParameters",
          "ssm:StartSession", "ssm:TerminateSession",
          "ssm:DescribeSessions", "ssm:GetConnectionStatus",
          # WAF permissions
          "wafv2:CreateWebACL",
          "wafv2:DeleteWebACL",
          "wafv2:GetWebACL",
          "wafv2:UpdateWebACL",
          "wafv2:ListWebACLs",
          "wafv2:TagResource",
          "wafv2:ListTagsForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:GetWebACLForResource",
          # CloudFront permissions
          "cloudfront:CreateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:TagResource",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation",
          # ACM permissions
          "acm:RequestCertificate",
          "acm:DeleteCertificate",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:AddTagsToCertificate",
          "acm:ListTagsForCertificate",
          # Route 53 permissions
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetChange",
          "route53:CreateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:GetHealthCheck",
          "route53:ListHealthChecks",
          "route53:UpdateHealthCheck",
          "route53:ListTagsForResource",
          "route53:ChangeTagsForResource",
          "autoscaling:PutScalingPolicy",
          "autoscaling:DeletePolicy",
          "autoscaling:DescribePolicies",
          # Route 53 health checks
          "route53:CreateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:GetHealthCheck",
          "route53:ListHealthChecks",
          "route53:UpdateHealthCheck",
          "route53:ListTagsForResource",
          "route53:ChangeTagsForResource",
          # Budgets
          "budgets:CreateBudget",
          "budgets:DeleteBudget",
          "budgets:DescribeBudget",
          "budgets:ModifyBudget",
          "budgets:ViewBudget",
          "budgets:ListTagsForResource",
          "budgets:TagResource",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "lab_networking" {
  user       = aws_iam_user.terraform_deployer.name
  policy_arn = aws_iam_policy.lab_networking.arn
}

# -----------------------------------------------------------------------------
# Policy 2 — Data & Secrets (RDS, ElastiCache, Secrets Manager, S3)
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "lab_data" {
  name        = "${var.project_name}-lab-data"
  description = "RDS, ElastiCache, Secrets Manager, S3 permissions for labs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance", "rds:DeleteDBInstance",
          "rds:DescribeDBInstances", "rds:ModifyDBInstance",
          "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups", "rds:ListTagsForResource",
          "rds:AddTagsToResource", "rds:DescribeDBParameterGroups",
          "rds:DescribeDBEngineVersions", "rds:DescribeOrderableDBInstanceOptions",
          "rds:DescribeCertificates", "rds:RebootDBInstance",
          "rds:DescribeEvents",
          "elasticache:CreateCacheCluster", "elasticache:DeleteCacheCluster",
          "elasticache:DescribeCacheClusters", "elasticache:ModifyCacheCluster",
          "elasticache:CreateCacheSubnetGroup", "elasticache:DeleteCacheSubnetGroup",
          "elasticache:DescribeCacheSubnetGroups",
          "elasticache:ListTagsForResource", "elasticache:AddTagsToResource",
          "elasticache:DescribeCacheParameterGroups",
          "elasticache:DescribeCacheEngineVersions",
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource", "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
          "s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketAcl",
          "s3:PutBucketAcl", "s3:GetBucketLocation", "s3:GetBucketPolicy",
          "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetBucketVersioning", "s3:PutBucketVersioning",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetBucketCORS", "s3:GetBucketLogging",
          "s3:GetBucketRequestPayment", "s3:GetBucketWebsite",
          "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:PutBucketEncryption",
          "s3:GetBucketEncryption"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "lab_data" {
  user       = aws_iam_user.terraform_deployer.name
  policy_arn = aws_iam_policy.lab_data.arn
}

# -----------------------------------------------------------------------------
# Policy 3 — Observability & IAM (CloudWatch, CloudTrail, GuardDuty,
#             EventBridge, SNS, IAM roles)
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "lab_observability" {
  name        = "${var.project_name}-lab-observability"
  description = "CloudWatch, CloudTrail, GuardDuty, IAM role permissions for labs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource",
          "cloudwatch:TagResource",
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:DescribeLogGroups", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:CreateLogStream",
          "logs:PutLogEvents", "logs:DescribeLogStreams",
          "logs:PutMetricFilter", "logs:DeleteMetricFilter",
          "logs:DescribeMetricFilters", "logs:ListTagsLogGroup",
          "logs:TagLogGroup", "logs:TagResource", "logs:ListTagsForResource",
          "cloudtrail:CreateTrail", "cloudtrail:DeleteTrail",
          "cloudtrail:DescribeTrails", "cloudtrail:GetTrailStatus",
          "cloudtrail:GetTrail", "cloudtrail:StartLogging",
          "cloudtrail:StopLogging", "cloudtrail:UpdateTrail",
          "cloudtrail:ListTags", "cloudtrail:AddTags",
          "cloudtrail:GetEventSelectors", "cloudtrail:PutEventSelectors",
          "cloudtrail:LookupEvents",
          "guardduty:CreateDetector", "guardduty:DeleteDetector",
          "guardduty:GetDetector", "guardduty:UpdateDetector",
          "guardduty:ListDetectors", "guardduty:TagResource",
          "guardduty:ListTagsForResource",
          "events:PutRule", "events:DeleteRule", "events:DescribeRule",
          "events:PutTargets", "events:RemoveTargets",
          "events:ListTargetsByRule", "events:ListTagsForResource",
          "events:TagResource",
          "sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes",
          "sns:SetTopicAttributes", "sns:ListTagsForResource",
          "sns:TagResource", "sns:Subscribe", "sns:Unsubscribe",
          "sns:ListSubscriptionsByTopic",
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:PassRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole", "iam:TagRole",
          "iam:TagInstanceProfile", "iam:PutRolePolicy",
          "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:CreateServiceLinkedRole", "iam:PutRolePolicy",
          # AWS Config permissions
          "config:PutConfigurationRecorder",
          "config:DeleteConfigurationRecorder",
          "config:DescribeConfigurationRecorders",
          "config:PutDeliveryChannel",
          "config:DeleteDeliveryChannel",
          "config:DescribeDeliveryChannels",
          "config:StartConfigurationRecorder",
          "config:StopConfigurationRecorder",
          "config:DescribeConfigurationRecorderStatus",
          "config:PutConfigRule",
          "config:DeleteConfigRule",
          "config:DescribeConfigRules",
          "config:TagResource",
          "config:ListTagsForResource",
          "iam:AttachRolePolicy",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "lab_observability" {
  user       = aws_iam_user.terraform_deployer.name
  policy_arn = aws_iam_policy.lab_observability.arn
}
