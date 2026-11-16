import {
  DynamoDBClient,
  PutItemCommand,
  DescribeTableCommand,
} from '@aws-sdk/client-dynamodb';

// Local gateway endpoint (e.g. LocalStack/Floci). When unset, the SDK uses its
// default configuration. AWS Emulator injects the function's role credentials and
// transparently routes AWS SDK calls back to itself, so no endpoint/creds override
// is needed there (and real AWS works the same way).
const ENDPOINT = process.env.AWS_ENDPOINT_URL;

const clientConfig: {
  region: string;
  endpoint?: string;
  credentials?: { accessKeyId: string; secretAccessKey: string };
} = {
  region: process.env.AWS_REGION || 'us-east-1',
};

if (ENDPOINT) {
  // Explicit local gateway that needs an endpoint + static test credentials.
  clientConfig.endpoint = ENDPOINT;
  clientConfig.credentials = {
    accessKeyId: 'test',
    secretAccessKey: 'test',
  };
}

const dynamoClient = new DynamoDBClient(clientConfig);
const ENDPOINT_LABEL = ENDPOINT || 'default (emulator/AWS-managed)';

const TABLE_NAME = process.env.TABLE_NAME || 'lambda-test-table';

export const handler = async (event: any) => {
  console.log('Event received:', JSON.stringify(event, null, 2));
  console.log('DynamoDB endpoint:', ENDPOINT_LABEL);

  try {
    const action = event.action || 'put';

    if (action === 'put') {
      return await putItemToDynamoDB(event);
    } else if (action === 'test') {
      return await testDynamoConnection();
    } else {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "Invalid action. Use 'put' or 'test'",
        }),
      };
    }
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : String(error),
      }),
    };
  }
};

async function putItemToDynamoDB(event: any) {
  const itemId = event.id || `item-${Date.now()}`;
  const itemData = event.data || 'test data from lambda';

  const params = {
    TableName: TABLE_NAME,
    Item: {
      id: { S: itemId },
      timestamp: { S: new Date().toISOString() },
      data: { S: itemData },
      source: { S: 'lambda-emulator' },
    },
  };

  await dynamoClient.send(new PutItemCommand(params));

  return {
    statusCode: 201,
    body: JSON.stringify({
      message: 'Item successfully written to DynamoDB',
      itemId: itemId,
      timestamp: new Date().toISOString(),
    }),
  };
}

async function testDynamoConnection() {
  try {
    const result = await dynamoClient.send(
      new DescribeTableCommand({ TableName: TABLE_NAME })
    );

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: '✅ Successfully connected to DynamoDB',
        endpoint: ENDPOINT_LABEL,
        table: TABLE_NAME,
        tableStatus: result.Table?.TableStatus,
        timestamp: new Date().toISOString(),
      }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: '❌ Failed to connect to DynamoDB',
        endpoint: ENDPOINT_LABEL,
        error: error instanceof Error ? error.message : String(error),
      }),
    };
  }
}
