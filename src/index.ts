export const handler = async (event: any) => {
  console.log("Event received:", JSON.stringify(event, null, 2));

  const response = {
    statusCode: 200,
    body: JSON.stringify({
      message: "Hello World from TypeScript Lambda!This is an updated source code",
      timestamp: new Date().toISOString(),
      event: event,
    }),
  };

  return response;
};
