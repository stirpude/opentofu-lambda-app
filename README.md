# OpenTofu Lambda TypeScript Application

This project uses OpenTofu (Terraform-compatible) to deploy a Lambda function written in TypeScript with a "Hello World" example.

## Project Structure

```
opentofu-lambda-app/
├── src/
│   ├── index.ts           # Lambda function code
│   ├── package.json       # Node.js dependencies
│   └── tsconfig.json      # TypeScript configuration
├── main.tf                # Main OpenTofu configuration
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── terraform.tfvars       # Variable values (optional)
└── README.md              # This file
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- OpenTofu or Terraform installed (v1.0+)
- Node.js and npm installed
- TypeScript knowledge (basic)

## Setup and Deployment

### 1. Initialize OpenTofu Workspace

```bash
cd opentofu-lambda-app
tofu init
```

Or with Terraform:
```bash
terraform init
```

### 2. Plan Deployment

```bash
tofu plan
```

### 3. Apply Configuration

```bash
tofu apply
```

### 4. Get Outputs

```bash
tofu output
```

## Configuration

Edit `terraform.tfvars` or pass variables via CLI:

```bash
tofu apply -var="aws_region=us-west-2" -var="function_name=my-lambda"
```

## Default Variables

- `aws_region`: us-east-1
- `function_name`: hello-world-typescript
- `runtime`: nodejs20.x
- `handler`: index.handler

## How It Works

1. **TypeScript Compilation**: The `null_resource` with `local-exec` provisioner compiles TypeScript to JavaScript
2. **Archive Creation**: The `archive_file` data source packages the compiled code into a ZIP file
3. **Lambda Deployment**: The Lambda function is created with the packaged code
4. **IAM Setup**: A dedicated IAM role is created with basic Lambda execution permissions

## Cleanup

To destroy all resources:

```bash
tofu destroy
```

## Files Generated During Build

- `src/dist/`: Compiled JavaScript output
- `src/node_modules/`: Node.js dependencies
- `lambda_function.zip`: Deployment package

These are ignored by `.gitignore` and should not be committed.

## Environment Variables

The Lambda function has the following environment variable set:
- `ENVIRONMENT=production`

## Function Handler

The Lambda handler is defined in `src/index.ts` and returns:
- Status Code: 200
- Body: JSON with message, timestamp, and event details

## Testing Locally

To test the Lambda function locally:

```bash
cd src
npm run build
node -e "const handler = require('./dist/index.js').handler; handler({test: true}).then(console.log);"
```

## Next Steps

- Add additional AWS resources (API Gateway, DynamoDB, etc.)
- Configure different environments (dev, staging, prod)
- Add CloudWatch alarms and monitoring
- Implement custom IAM policies for specific AWS services
