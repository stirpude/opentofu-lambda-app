# OIDC Troubleshooting Guide

If the GitHub Actions workflow is stuck on "Assuming role with OIDC", the issue is with the AWS IAM role configuration.

## Required IAM Role Configuration

Your GitHub Actions workflow needs an IAM role with the correct **trust policy** (trust relationship).

### Check Your IAM Role Trust Policy

1. Go to **AWS Console** → **IAM** → **Roles**
2. Find and click on: `GitHubRole-Role-EnNpHp52UHLI`
3. Click the **Trust relationships** tab
4. The trust policy should look like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::391122274211:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:stirpude/opentofu-lambda-app:*"
        }
      }
    }
  ]
}
```

### Key Things to Verify

1. **OIDC Provider exists**: `arn:aws:iam::391122274211:oidc-provider/token.actions.githubusercontent.com`
   - If not, you need to create it in IAM → Identity providers

2. **Subject claim matches**: `repo:stirpude/opentofu-lambda-app:*`
   - Must match your GitHub username and repository name
   - The `*` at the end allows any branch/environment

3. **Action is correct**: `sts:AssumeRoleWithWebIdentity`

4. **Audience is correct**: `sts.amazonaws.com`

### If the Trust Policy is Wrong

Edit the **Trust relationships** in the IAM role and replace with the JSON above, updating:
- Your AWS account ID (391122274211)
- Your GitHub repo path (stirpude/opentofu-lambda-app)

## Deploy Script Alternative

If you continue to have issues, you can deploy locally:

```bash
cd opentofu
tofu init
tofu plan
tofu apply
```

This requires AWS credentials configured locally (via `aws configure` or environment variables).
