# GitHub Actions Setup Guide

This guide explains how to set up GitHub Actions for automated deployment of the OpenTofu Lambda infrastructure.

## Prerequisites

1. GitHub repository with this code
2. AWS account with appropriate permissions
3. IAM role with OpenTofu/Terraform permissions

## Setup Steps

### 1. Create AWS IAM Role for GitHub Actions

Follow AWS documentation to create an OpenID Connect (OIDC) provider and IAM role:

**Option A: Using AWS Management Console**

1. Go to IAM → Identity Providers
2. Create OIDC provider with URL: `https://token.actions.githubusercontent.com`
3. Audience: `sts.amazonaws.com`
4. Create IAM role with trust relationship for GitHub

**Option B: Using AWS CLI**

```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Attach policy to the role (example minimal policy below)
```

### 2. Create IAM Policy

Create a policy with the following permissions for Lambda and related services:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "arn:aws:lambda:*:*:function/*"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/*"
    },
    {
      "Sid": "S3AccessForState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::*terraform*/*"
    }
  ]
}
```

### 3. Configure GitHub Repository Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

```
AWS_ROLE_TO_ASSUME = arn:aws:iam::ACCOUNT_ID:role/github-actions-role
```

Replace `ACCOUNT_ID` with your AWS account ID and `github-actions-role` with your role name.

### 4. Update OpenTofu State Storage (Optional but Recommended)

For production, configure remote state backend:

**Create S3 backend configuration (backend.tf):**

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "lambda/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

Then create the S3 bucket and DynamoDB table:

```bash
# Create S3 bucket
aws s3api create-bucket --bucket your-terraform-state-bucket --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locks
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## Workflow Behavior

### Deploy Workflow (`deploy.yml`)

**Triggers:**
- Push to `main` branch (automatic deployment)
- Pull Request to `main` (planning only with comment)
- Manual trigger via `workflow_dispatch`

**Jobs:**
1. **Plan** - Validates and plans infrastructure changes
   - Checks Terraform format
   - Creates plan
   - Comments on PRs with the plan

2. **Apply** - Deploys infrastructure (only on push to main)
   - Applies the planned changes
   - Outputs Lambda function details
   - Creates deployment summary

### Destroy Workflow (`destroy.yml`)

**Triggers:**
- Manual trigger via `workflow_dispatch` in Actions tab

**Safety Feature:**
- Requires typing "destroy" as confirmation input

## Usage Examples

### Automatic Deployment

1. Make changes to `main.tf` or `src/index.ts`
2. Push to `main` branch
3. GitHub Actions automatically deploys

### Preview Changes

1. Create a pull request to `main`
2. GitHub Actions plans the changes
3. Plan comments appear on the PR for review
4. Once approved, merge to deploy

### Manual Trigger

1. Go to Actions tab in GitHub
2. Select "Deploy Lambda with OpenTofu"
3. Click "Run workflow"
4. Select branch and click Run

### Destroy Resources

1. Go to Actions tab
2. Select "Destroy Infrastructure"
3. Click "Run workflow"
4. Enter "destroy" as confirmation
5. Click Run

## Environment Variables

The workflows use the following environment variables:

- `AWS_REGION`: us-east-1 (modify in workflow file as needed)
- `TF_VERSION`: 1.6.0 (OpenTofu version)

## Troubleshooting

### "AssumeRoleUnauthorizedOperation" Error

- Verify OIDC provider is configured correctly
- Check IAM role trust relationship
- Ensure AWS_ROLE_TO_ASSUME secret is correct

### Terraform State Lock Error

- Previous workflow may still be running
- Check workflow history and cancel if stuck
- Or manually unlock state: `tofu force-unlock <LOCK_ID>`

### Plan Not Showing in PR

- Verify GitHub token has PR write permissions
- Check workflow permissions in Settings

### Node.js Dependencies Not Found

- Ensure `npm install` runs in src directory
- Check that package.json exists in src/

## Advanced Configuration

### Add Slack Notifications

Add to workflow steps:

```yaml
- name: Notify Slack
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Lambda deployment completed",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Lambda Function:* ${{ steps.outputs.outputs.lambda_name }}"
            }
          }
        ]
      }
```

### Add Approval Gate

Modify deploy.yml to require manual approval before apply:

```yaml
apply:
  needs: [plan, approval]
  if: github.ref == 'refs/heads/main'
```

And add approval job before apply job.

### Custom Terraform Variables

Create `terraform.tfvars` in repo (or add to secrets):

```bash
tofu apply -var-file=terraform.tfvars -auto-approve
```

## Security Best Practices

1. ✅ Use OIDC instead of long-lived AWS credentials
2. ✅ Limit IAM permissions to minimum required
3. ✅ Enable S3 backend encryption
4. ✅ Use DynamoDB table for state locking
5. ✅ Require PR reviews before merging
6. ✅ Enable branch protection rules
7. ✅ Regularly audit workflow logs
8. ✅ Rotate OpenID Connect thumbprint annually

## Additional Resources

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
