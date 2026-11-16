# Source this file to point the AWS CLI / SDK at the local AWS Emulator.
#   source emulator-env.sh
# Assumes the emulator runs on port 9297 (see README.md).

PORT="${EMULATOR_PORT:-9297}"

export AWS_ENDPOINT_URL="https://127.0.0.1:${PORT}"
export AWS_CA_BUNDLE="$HOME/.aws/emulator/${PORT}/ca.pem"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_EC2_METADATA_DISABLED="true"

# Use a Node.js version matching the Lambda runtime (nodejs20.x) if nvm is present.
if [ -d "$HOME/.nvm/versions/node/v20.20.2/bin" ]; then
  export PATH="$HOME/.nvm/versions/node/v20.20.2/bin:$PATH"
fi

echo "AWS CLI/SDK pointed at AWS Emulator: $AWS_ENDPOINT_URL"
echo "Note: aws-cli < 2.13 ignores AWS_ENDPOINT_URL; pass --endpoint-url \"$AWS_ENDPOINT_URL\" --ca-bundle \"$AWS_CA_BUNDLE\" explicitly."
