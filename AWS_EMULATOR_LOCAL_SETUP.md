# Local Lambda + DynamoDB with AWS Emulator

Run the TypeScript Lambda and its DynamoDB table **locally** via the
[AWS Emulator](https://github.com/aws/aws-emulator) — no AWS account.
All files are in the **`local/`** folder.

## How it works

The emulator is a Docker container serving the AWS API on `https://127.0.0.1:9297`
(self-signed cert, state in memory). It runs a **real nodejs20.x runtime**, so
`lambda invoke` executes your handler; it **injects the role's credentials**,
**routes the SDK calls back to itself**, and **enforces IAM** — just like AWS.
Restarting the container wipes all resources.

## Prerequisites

Docker · OpenTofu ≥ 1.0 · Node 20 (`nvm use 20`) · AWS CLI.
Apple Silicon uses the `aarch64` package in the `Dockerfile` (change to `x86_64` on Intel).

---

## Option A — one command (CLI)

```bash
cd local
./start-and-provision.sh      # build image, start container, create table + role + Lambda
```

`provision-cli.sh` does the same against an already-running container. Both are idempotent.

---

## Option B — manual AWS CLI steps

**1. Build image (first time):**
```bash
cd local && docker build -t aws-emulator .
```

**2. Start the emulator:**
```bash
mkdir -p ~/.aws/emulator
docker run -d --name aws-emulator --memory=2g --memory-swap=2g \
  -p 127.0.0.1:9297:9297 -e HOME="$HOME" \
  -v "$HOME/.aws/emulator:$HOME/.aws/emulator" \
  aws-emulator -p 9297 -a off
curl -s --cacert ~/.aws/emulator/9297/ca.pem https://127.0.0.1:9297/__admin/health   # -> ok
```
`-a off` disables SigV4 so dummy creds work; HTTPS cert is at `~/.aws/emulator/9297/ca.pem`.

**3. Point the shell at the emulator:**
```bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
E="--endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem"
```
> **zsh** doesn't word-split variables, so `aws $E ...` fails. Use a helper:
> ```zsh
> awsx() { aws --endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem --region us-east-1 "$@"; }
> ```
> Then use `awsx ...` instead of `aws $E ...` below (or `${=E}`, or type the flags literally).

**4. Create table, role + policy, and Lambda:**
```bash
aws $E dynamodb create-table --table-name lambda-test-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST

aws $E iam create-role --role-name my-func-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Action":"sts:AssumeRole","Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"}}]}'

aws $E iam put-role-policy --role-name my-func-role --policy-name my-func-dynamodb \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:PutItem","dynamodb:DescribeTable"],"Resource":"*"}]}'

# build + zip the code
( cd ../src-local && nvm use 20 && npm install && npm run build && rm -f function.zip && cd dist && zip -qr ../function.zip . )

aws $E lambda create-function --function-name my-func \
  --runtime nodejs20.x --handler index.handler \
  --role arn:aws:iam::000000000000:role/my-func-role \
  --environment 'Variables={TABLE_NAME=lambda-test-table}' \
  --zip-file fileb://../src-local/function.zip
```
Emulator account ID is always `000000000000`.

---

## Option C — OpenTofu

> Run from `local/` only (not the project's `opentofu/` folder, which is the real-AWS config).

```bash
cd local
nvm use 20
tofu init                 # first time
tofu apply -auto-approve  # creates table + role/policy + Lambda
tofu destroy -auto-approve
```
`provider.tf` points the services at the emulator; `main.tf` defines the resources.

---

## Invoke and verify

Handler actions: `put` (write item), `test` (connectivity via DescribeTable).

```bash
aws $E lambda invoke --function-name my-func --cli-binary-format raw-in-base64-out \
  --payload '{"action":"put","id":"order-123","data":"hello"}' out.json && cat out.json

aws $E dynamodb scan --table-name lambda-test-table
```
`--cli-binary-format raw-in-base64-out` is required so the payload isn't read as base64.
The handler's real response is in `out.json` (terminal shows only `StatusCode`).

## Tear down

```bash
docker rm -f aws-emulator      # in-memory state is lost
```

## Files (`local/`)

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the emulator image |
| `start-and-provision.sh` | Start container + create all resources |
| `provision-cli.sh` | Create resources on a running container (idempotent) |
| `provider.tf` / `variables.tf` / `main.tf` | OpenTofu config |
| `README.md` | Folder reference |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `argument command: Invalid choice` | `$E` is empty — re-run step 3 or pass flags literally |
| `zsh: no such file or directory: aws --endpoint-url ...` | zsh — use the `awsx` function or `${=E}` |
| `Invalid base64` on invoke | add `--cli-binary-format raw-in-base64-out` |
| `Requested resource not found` from Lambda | table missing — create it (step 4) |
| `AccessDeniedException dynamodb:*` | role missing DynamoDB policy (step 4) |
| Resources gone after restart | expected (in-memory) — re-provision |
| `SSL validation failed` | add `--ca-bundle ~/.aws/emulator/9297/ca.pem` |
| `??=` / npm error on build | use Node 20 (`nvm use 20`) |
| `Duplicate provider`/`resource` on `tofu init` | wrong folder — run in `local/` |
| Perpetual `on_demand_throughput` diff | harmless emulator quirk |
