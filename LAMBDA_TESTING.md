# Lambda Function Testing Guide

## Test Events

The `test-events.json` file contains sample test events for your Lambda function.

### Using test-events.json in AWS Console

1. **Navigate to your Lambda function** in AWS Console
2. **Click the "Test" tab** at the top
3. **Select or create a test event**
4. **Copy one of the events** from `test-events.json`:
   - `test_basic` - Simple event with basic fields
   - `test_api_gateway` - API Gateway proxy format event
   - `test_with_data` - Event with structured data payload

5. **Paste into the test editor** and click "Test"

### Testing Locally with SAM or Direct Invocation

#### Option 1: Using AWS CLI
```bash
# Using the basic test event
aws lambda invoke \
  --function-name hello-world-typescript \
  --payload file://test-events.json \
  --region us-east-1 \
  response.json

# View the response
cat response.json
```

#### Option 2: Using a Specific Test Event
```bash
# Extract a specific test event and invoke
aws lambda invoke \
  --function-name hello-world-typescript \
  --payload '{"message":"Hello from Lambda","source":"test-event"}' \
  --region us-east-1 \
  response.json
```

### Expected Response

When you invoke the Lambda function with any of the test events, you should receive:

```json
{
  "statusCode": 200,
  "body": "{\"message\":\"Hello World from TypeScript Lambda!\",\"timestamp\":\"2026-04-03T10:30:00Z\",\"event\":{...your test event...}}"
}
```

### Test Events Explanation

#### test_basic - Simple Event
```json
{
  "message": "Hello from Lambda",
  "source": "test-event"
}
```
**Use for:** Quick basic testing

#### test_api_gateway - API Gateway Proxy Format
```json
{
  "resource": "/",
  "path": "/",
  "httpMethod": "GET",
  "headers": { ... },
  "queryStringParameters": {
    "name": "John",
    "city": "New York"
  },
  "body": null,
  "isBase64Encoded": false
}
```
**Use for:** Testing Lambda integrated with API Gateway

#### test_with_data - Event with Payload Data
```json
{
  "action": "process",
  "data": {
    "id": "12345",
    "name": "Test User",
    "email": "test@example.com"
  },
  "timestamp": "2026-04-03T10:30:00Z"
}
```
**Use for:** Testing with structured data

### Monitoring

Check CloudWatch Logs to see your Lambda function's output:

1. Go to **CloudWatch** → **Log Groups**
2. Find `/aws/lambda/hello-world-typescript`
3. Click on the latest log stream
4. You'll see your console.log outputs and any errors

### Troubleshooting

If the Lambda function fails:
- Check the error message in the Test console
- Review CloudWatch logs for detailed error information
- Verify the IAM role has proper permissions
- Check that the function was deployed successfully (check the `lambda_outputs.json` artifact from GitHub Actions)
