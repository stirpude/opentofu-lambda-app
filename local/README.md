# Local Lambda + DynamoDB with AWS Emulator

This stack provisions and runs the TypeScript Lambda and its DynamoDB table
**entirely locally** using the [AWS Emulator](https://github.com/aws/aws-emulator)
— no AWS account, no deployment. OpenTofu talks to the emulator exactly as it
would to AWS.

## Quick start (AWS CLI only — no OpenTofu)

If you just want the container up and resources created via the AWS CLI:

```bash
cd local
./start-and-provision.sh     # builds image if needed, starts emulator, creates all resources
```

Or, if your container is already running:

```bash
cd local
./provision-cli.sh           # creates DynamoDB table, IAM role/policy, Lambda, runs a smoke test
```

Both scripts are idempotent (safe to re-run) and finish with a working
`my-func` Lambda + `lambda-test-table`. The rest of this document describes the
OpenTofu path and the manual steps.


## Why AWS Emulator (vs. the LocalStack config in `opentofu/local/`)

The emulator is generated from AWS API models and aims for full fidelity on
supported operations. Key behaviors verified for this stack:

- It runs a **real `nodejs20.x` runtime** — `lambda:Invoke` executes your handler.
- It **injects the function role's credentials** and **routes the SDK calls back
  to itself**, so the handler needs no endpoint/credentials override.
- It **enforces IAM** — the role must have an explicit DynamoDB policy, just like AWS.

The handler (`src-local/index.ts`) was made portable: it only overrides the
endpoint/credentials when `AWS_ENDPOINT_URL` is set (LocalStack/Floci mode);
otherwise it uses default SDK config (emulator and real AWS).

## Prerequisites

- Docker (Rancher Desktop/Docker Desktop)
- OpenTofu (or Terraform) ≥ 1.0
- Node.js 20 (matches the Lambda runtime; `nvm use 20`)
- AWS CLI (any version; < 2.13 needs explicit `--endpoint-url`/`--ca-bundle`)

## Step 1 — Build the emulator image

> No prebuilt image is published. On Apple Silicon the Dockerfile uses the
> `aarch64` RPM; change it to `x86_64` on Intel.

```bash
cd local
docker build -t aws-emulator .
```

## Step 2 — Run the emulator

```bash
mkdir -p ~/.aws/emulator
docker run -d --name aws-emulator --memory=2g --memory-swap=2g \
  -p 127.0.0.1:9297:9297 \
  -e HOME="$HOME" \
  -v "$HOME/.aws/emulator:$HOME/.aws/emulator" \
  aws-emulator -p 9297 -a off

# health check
curl -s --cacert ~/.aws/emulator/9297/ca.pem https://127.0.0.1:9297/__admin/health   # -> ok
```

`-a off` disables SigV4 checks so the OpenTofu provider can use dummy static
credentials. The emulator still serves HTTPS with a self-signed cert
(`~/.aws/emulator/9297/ca.pem`). To require signatures instead, drop `-a off`
and wire the generated `emulator_credentials` into the provider.

## Step 3 — Provision with OpenTofu

```bash
nvm use 20        # the TS build (invoked by OpenTofu) needs Node 18+/20
tofu init
tofu apply -auto-approve
```

This creates: DynamoDB table, IAM role + DynamoDB policy, and the Lambda
function (built from `../src-local`).

## Step 4 — Invoke the Lambda end-to-end

```bash
source emulator-env.sh     # exports creds + CA bundle; adds Node 20 to PATH
E="--endpoint-url $AWS_ENDPOINT_URL --ca-bundle $AWS_CA_BUNDLE"

# write an item through the Lambda
aws $E lambda invoke --function-name my-func --cli-binary-format raw-in-base64-out \
  --payload '{"action":"put","id":"order-123","data":"hello"}' out.json && cat out.json

# check connectivity through the Lambda
aws $E lambda invoke --function-name my-func --cli-binary-format raw-in-base64-out \
  --payload '{"action":"test"}' out.json && cat out.json

# verify directly against the emulator's DynamoDB
aws $E dynamodb scan --table-name lambda-test-table
```

Supported `action` values: `put`, `test`.

## Step 5 — Tear down

```bash
tofu destroy -auto-approve      # remove emulated resources
docker rm -f aws-emulator       # stop the emulator (in-memory state is lost)
```

## Notes

- State is in-memory: restarting the container wipes all resources; re-run
  `tofu apply`.
- The emulator collects telemetry by default; disable with `EMULATOR_TELEMETRY=off`
  (env) or in `~/.aws/emulator/config.toml`.
- For production/CI, prefer SigV4 (`-a on`) and bind to loopback (`-b 127.0.0.1`).
- Known fidelity quirk: `tofu plan` may show a perpetual harmless in-place update
  on the DynamoDB table (`on_demand_throughput` reported as `-1` instead of null by
  the emulator's `DescribeTable`). It does not affect behavior.
