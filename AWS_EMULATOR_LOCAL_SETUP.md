# Local Lambda + DynamoDB with AWS Emulator — Step by Step

This guide explains how to run the project's TypeScript Lambda and its DynamoDB
table **entirely on your machine** using the
[AWS Emulator](https://github.com/aws/aws-emulator) — no AWS account, no cloud
deployment. Your normal AWS CLI / SDK calls go to the emulator and come back in
milliseconds.

All files referenced here live in the **`local/`** folder at the project root.

---

## 1. How it works

```
          aws / tofu CLI                      Docker container
   (AWS SDK calls, SigV4-signed)            ┌───────────────────────┐
  ──────────────────────────────────►       │   AWS Emulator        │
     https://127.0.0.1:9297                  │   (in-memory state)   │
                                             │   - Lambda runtime    │
                                             │   - DynamoDB          │
                                             │   - IAM / STS         │
                                             └───────────────────────┘
```

Key facts about the emulator, verified for this project:

- It runs a **real `nodejs20.x` runtime**, so `lambda invoke` actually executes
  the handler code.
- When a Lambda runs, the emulator **injects the function role's credentials**
  and **routes the SDK calls back to itself** — the handler needs no endpoint or
  credential override.
- It **enforces IAM** — the role must have an explicit DynamoDB policy, exactly
  like real AWS.
- State is kept **in memory**. Stopping/restarting the container wipes all
  resources, so you re-provision after each start.

---

## 2. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Docker | any recent | Rancher Desktop or Docker Desktop |
| OpenTofu / Terraform | ≥ 1.0 | Only for the OpenTofu path (section 6) |
| Node.js | 20.x | Matches the Lambda runtime; `nvm use 20` |
| AWS CLI | any | v < 2.13 ignores `AWS_ENDPOINT_URL`; pass `--endpoint-url`/`--ca-bundle` explicitly |

> On Apple Silicon the `Dockerfile` uses the `aarch64` emulator package. On
> Intel, change it to `x86_64`.

---

## 3. Fastest path — one command

```bash
cd local
./start-and-provision.sh
```

This script:
1. Builds the `aws-emulator` image if it doesn't exist.
2. (Re)starts the container on `127.0.0.1:9297`.
3. Waits for the emulator health check.
4. Builds + zips the Lambda from `src-local/`.
5. Creates the DynamoDB table, IAM role + policy, and the Lambda.
6. Runs a smoke test (writes an item, prints the response).

When it finishes you have a working `my-func` Lambda and `lambda-test-table`.

---

## 4. Step-by-step with the AWS CLI (no OpenTofu)

Use this if you want to understand or run each step yourself.

### 4.1 Build the emulator image (first time only)

```bash
cd local
docker build -t aws-emulator .
```

### 4.2 Start the emulator container

```bash
mkdir -p ~/.aws/emulator
docker run -d --name aws-emulator --memory=2g --memory-swap=2g \
  -p 127.0.0.1:9297:9297 \
  -e HOME="$HOME" \
  -v "$HOME/.aws/emulator:$HOME/.aws/emulator" \
  aws-emulator -p 9297 -a off

# health check — expect: ok
curl -s --cacert ~/.aws/emulator/9297/ca.pem https://127.0.0.1:9297/__admin/health; echo
```

`-a off` turns off SigV4 signature checks so you can use dummy credentials. The
emulator still serves HTTPS with a self-signed certificate at
`~/.aws/emulator/9297/ca.pem`.

### 4.3 Point your shell at the emulator

Run this **once per terminal**. If `echo` shows empty flags, you're in a
different tab than where you set them.

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
CA=~/.aws/emulator/9297/ca.pem
E="--endpoint-url https://127.0.0.1:9297 --ca-bundle $CA"
echo "E=[$E]"      # must print the flags, not E=[]
```

> **zsh users:** unlike bash, zsh does **not** word-split an unquoted variable,
> so `aws $E ...` fails with `no such file or directory: aws --endpoint-url ...`.
> Use one of these instead:
>
> ```zsh
> # Option A — define a helper function (recommended)
> awsx() { aws --endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem --region us-east-1 "$@"; }
> export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
> awsx dynamodb list-tables         # then use `awsx ...` everywhere
>
> # Option B — force word-splitting of the variable
> ${=E} dynamodb list-tables
>
> # Option C — type the flags literally on each command
> aws --endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem --region us-east-1 dynamodb list-tables
> ```
>
> In the examples below, `aws $E ...` works as-is in **bash**. In **zsh**, read
> `aws $E` as `awsx` (Option A).

### 4.4 Create the DynamoDB table

```bash
aws $E dynamodb create-table --table-name lambda-test-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### 4.5 Create the IAM role and DynamoDB policy

```bash
aws $E iam create-role --role-name my-func-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Action":"sts:AssumeRole","Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"}}]}'

aws $E iam put-role-policy --role-name my-func-role \
  --policy-name my-func-dynamodb \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:PutItem","dynamodb:DescribeTable"],"Resource":"*"}]}'
```

### 4.6 Build and zip the Lambda code

```bash
cd ../src-local
nvm use 20
npm install && npm run build
rm -f function.zip && (cd dist && zip -qr ../function.zip .)
cd ../local
```

### 4.7 Create the Lambda function

```bash
aws $E lambda create-function --function-name my-func \
  --runtime nodejs20.x --handler index.handler \
  --role arn:aws:iam::000000000000:role/my-func-role \
  --environment 'Variables={TABLE_NAME=lambda-test-table}' \
  --zip-file fileb://../src-local/function.zip
```

> The emulator account ID is always `000000000000`.

---

## 5. Invoke and verify

The handler supports two actions via the payload: `put` (write an item) and
`test` (check connectivity via DescribeTable).

```bash
# write an item THROUGH the Lambda
aws $E lambda invoke --function-name my-func \
  --cli-binary-format raw-in-base64-out \
  --payload '{"action":"put","id":"order-123","data":"hello"}' out.json
cat out.json          # -> statusCode 201, "Item successfully written to DynamoDB"

# check connectivity THROUGH the Lambda
aws $E lambda invoke --function-name my-func \
  --cli-binary-format raw-in-base64-out \
  --payload '{"action":"test"}' out.json
cat out.json

# verify directly against the emulator's DynamoDB
aws $E dynamodb list-tables
aws $E dynamodb scan --table-name lambda-test-table
```

Notes:
- `--cli-binary-format raw-in-base64-out` is required so the CLI doesn't treat
  the JSON payload as base64 (seen on aws-cli 2.7).
- The terminal shows only `{"StatusCode":200,...}`; the handler's real response
  is written to `out.json`.

---

## 6. Alternative — create resources with OpenTofu

Instead of the AWS CLI, you can let **OpenTofu** create the same resources
declaratively. This talks to the emulator exactly as it would to real AWS.

> **Run OpenTofu from the `local/` folder only.** Do **not** run it in the
> project's `opentofu/` folder for emulator testing — that folder is the
> real-AWS deployment config.

### 6.1 Start the emulator (if not already running)

```bash
cd local
docker run -d --name aws-emulator --memory=2g --memory-swap=2g \
  -p 127.0.0.1:9297:9297 -e HOME="$HOME" \
  -v "$HOME/.aws/emulator:$HOME/.aws/emulator" \
  aws-emulator -p 9297 -a off
sleep 4
curl -s --cacert ~/.aws/emulator/9297/ca.pem https://127.0.0.1:9297/__admin/health; echo   # -> ok
```

### 6.2 Initialize and apply

```bash
cd local
nvm use 20           # the TS build that OpenTofu triggers needs Node 20
tofu init            # first time only — downloads providers
tofu plan            # preview the changes
tofu apply -auto-approve
```

This creates the DynamoDB table, IAM role + policy and the Lambda. On success
you'll see outputs:

```
emulator_endpoint = "https://127.0.0.1:9297"
function_arn      = "arn:aws:lambda:us-east-1:000000000000:function:my-func"
function_name     = "my-func"
table_name        = "lambda-test-table"
```

- `provider.tf` points Lambda, DynamoDB, IAM, STS and Logs at the emulator
  endpoint (HTTPS, self-signed cert, dummy static credentials).
- `variables.tf` holds the region, endpoint, resource names and source dir.
- `main.tf` defines the table, role + policy and function.

### 6.3 Verify the OpenTofu-created resources

```bash
tofu output          # shows function_arn, table_name, emulator_endpoint

# invoke the function (bash). In zsh, use the awsx helper from section 4.3.
aws --endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem --region us-east-1 \
  lambda invoke --function-name my-func --cli-binary-format raw-in-base64-out \
  --payload '{"action":"put","id":"tf-1","data":"from tofu"}' out.json && cat out.json

# confirm the item landed in DynamoDB
aws --endpoint-url https://127.0.0.1:9297 --ca-bundle ~/.aws/emulator/9297/ca.pem --region us-east-1 \
  dynamodb scan --table-name lambda-test-table
```

### 6.4 Destroy

```bash
cd local
tofu destroy -auto-approve
```

### OpenTofu gotchas with the emulator

- **Don't mix** the CLI scripts (`provision-cli.sh`) and OpenTofu against the
  same running emulator. The scripts create resources OpenTofu's state doesn't
  know about, which causes `EntityAlreadyExists` on `tofu apply`. Restart the
  container (wipes in-memory state) before switching methods.
- **In-memory state:** after you restart the container, the emulator is empty
  but `terraform.tfstate` still lists the old resources. Re-run `tofu apply`
  (it will recreate them). If apply errors on an already-"tracked" resource,
  run `tofu destroy` or start from a fresh state.
- **Perpetual harmless diff:** `tofu plan` may always show a 1-resource in-place
  update on the DynamoDB table (`on_demand_throughput = -1 -> null`). This is an
  emulator `DescribeTable` fidelity quirk and does not affect behavior.
- **`Duplicate provider` / `Duplicate resource` errors on `tofu init`:** you're
  running in the wrong folder (the project's `opentofu/` dir). Use `local/`.

---

## 7. Tear down

```bash
# remove emulated resources (OpenTofu path)
cd local && tofu destroy -auto-approve

# stop the emulator (in-memory state is lost)
docker rm -f aws-emulator
```

---

## 8. File reference (`local/`)

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the emulator image from the AWS Emulator package |
| `start-and-provision.sh` | Start container **and** create all resources (one command) |
| `provision-cli.sh` | Create resources against an already-running container (idempotent) |
| `emulator-env.sh` | `source` it to export creds + CA bundle for the CLI |
| `provider.tf` | OpenTofu AWS provider pointed at the emulator |
| `variables.tf` | Region, endpoint, names, source directory |
| `main.tf` | DynamoDB table + IAM role/policy + Lambda (OpenTofu) |
| `README.md` | Condensed reference for this folder |

---

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `aws: error: argument command: Invalid choice` | `$E` is empty in this shell. Re-run the exports in section 4.3, or pass `--endpoint-url`/`--ca-bundle` literally. |
| `zsh: no such file or directory: aws --endpoint-url ...` | zsh doesn't word-split variables. Use the `awsx` function or `${=E}` (section 4.3). |
| `Invalid base64` on invoke | Add `--cli-binary-format raw-in-base64-out`. |
| `Requested resource not found` from the Lambda | DynamoDB table missing — run section 4.4. |
| `AccessDeniedException ... dynamodb:*` | Role missing the DynamoDB policy — run section 4.5. |
| `EntityAlreadyExists` / `ResourceConflict` | Resource already created; it's safe. The scripts handle this idempotently. |
| Resources gone after restart | Expected — emulator state is in memory. Re-run `./start-and-provision.sh`. |
| `SSL validation failed` | Missing `--ca-bundle ~/.aws/emulator/9297/ca.pem` (or `AWS_CA_BUNDLE`). |
| Build fails with `??=` / npm error | Wrong Node version. Use Node 20 (`nvm use 20`). |
