#!/usr/bin/env bash
#
# provision-cli.sh — create the DynamoDB table, IAM role/policy and Lambda
# function in a running AWS Emulator, using only the AWS CLI (no OpenTofu).
#
# Run it after the emulator container is up:
#   ./provision-cli.sh
#
# Or use ./start-and-provision.sh to start the container AND run this script.
#
set -euo pipefail

# ---- Config (override via environment) --------------------------------------
PORT="${EMULATOR_PORT:-9297}"
ENDPOINT="https://127.0.0.1:${PORT}"
CA="${AWS_CA_BUNDLE:-$HOME/.aws/emulator/${PORT}/ca.pem}"
REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-my-func}"
ROLE_NAME="${FUNCTION_NAME}-role"
TABLE_NAME="${TABLE_NAME:-lambda-test-table}"
NODE_VERSION="${NODE_VERSION:-20.20.2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src-local"
ZIP_PATH="$SRC_DIR/function.zip"

# Dummy credentials the emulator accepts (SigV4 with any key when started -a off).
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

AWS=(aws --endpoint-url "$ENDPOINT" --ca-bundle "$CA" --region "$REGION")

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# ---- 1. Wait for the emulator health check ----------------------------------
log "Waiting for AWS Emulator at $ENDPOINT ..."
for i in $(seq 1 30); do
  if [ -f "$CA" ] && curl -sf --cacert "$CA" "$ENDPOINT/__admin/health" >/dev/null 2>&1; then
    log "Emulator is healthy."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: emulator did not become healthy at $ENDPOINT" >&2
    echo "       Is the container running and is $CA present?" >&2
    exit 1
  fi
  sleep 1
done

# ---- 2. Build + zip the Lambda ----------------------------------------------
log "Building Lambda from $SRC_DIR ..."
# Use a Node version matching the nodejs20.x runtime if nvm is available.
if [ -d "$HOME/.nvm/versions/node/v${NODE_VERSION}/bin" ]; then
  export PATH="$HOME/.nvm/versions/node/v${NODE_VERSION}/bin:$PATH"
fi
(
  cd "$SRC_DIR"
  npm install >/dev/null 2>&1
  npm run build >/dev/null 2>&1
  rm -f function.zip
  (cd dist && zip -qr ../function.zip .)
)
log "Packaged $ZIP_PATH"

# ---- 3. DynamoDB table ------------------------------------------------------
if "${AWS[@]}" dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1; then
  log "DynamoDB table '$TABLE_NAME' already exists."
else
  log "Creating DynamoDB table '$TABLE_NAME' ..."
  "${AWS[@]}" dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi

# ---- 4. IAM role + DynamoDB policy ------------------------------------------
if "${AWS[@]}" iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  log "IAM role '$ROLE_NAME' already exists."
else
  log "Creating IAM role '$ROLE_NAME' ..."
  "${AWS[@]}" iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Action":"sts:AssumeRole","Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"}}]}' >/dev/null
fi

log "Attaching DynamoDB policy to '$ROLE_NAME' ..."
"${AWS[@]}" iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "${FUNCTION_NAME}-dynamodb" \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:PutItem","dynamodb:DescribeTable"],"Resource":"*"}]}' >/dev/null

# ---- 5. Lambda function -----------------------------------------------------
ROLE_ARN="arn:aws:iam::000000000000:role/${ROLE_NAME}"
if "${AWS[@]}" lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  log "Lambda '$FUNCTION_NAME' exists; updating code ..."
  "${AWS[@]}" lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" >/dev/null
else
  log "Creating Lambda '$FUNCTION_NAME' ..."
  "${AWS[@]}" lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime nodejs20.x --handler index.handler \
    --role "$ROLE_ARN" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --zip-file "fileb://$ZIP_PATH" >/dev/null
fi

# ---- 6. Smoke test ----------------------------------------------------------
log "Invoking '$FUNCTION_NAME' (action=put) ..."
OUT="$(mktemp)"
"${AWS[@]}" lambda invoke --function-name "$FUNCTION_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"action":"put","id":"provision-check","data":"created via provision-cli.sh"}' \
  "$OUT" >/dev/null
echo "    response: $(cat "$OUT")"
rm -f "$OUT"

log "Done. Resources created in the emulator:"
echo "    - DynamoDB table : $TABLE_NAME"
echo "    - IAM role       : $ROLE_NAME"
echo "    - Lambda         : $FUNCTION_NAME"
echo
echo "Try it:"
echo "  aws --endpoint-url $ENDPOINT --ca-bundle $CA --region $REGION \\"
echo "    lambda invoke --function-name $FUNCTION_NAME --cli-binary-format raw-in-base64-out \\"
echo "    --payload '{\"action\":\"test\"}' out.json && cat out.json"
