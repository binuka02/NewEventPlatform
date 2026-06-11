const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const s3Client = new S3Client({
  region: process.env.AWS_REGION || "us-east-1",
});
const BUCKET_NAME =
  process.env.S3_BUCKET || "new-event-notifications-896328677531";

exports.handler = async (event) => {
  console.log("Low seat alert triggered:", JSON.stringify(event));

  try {
    const { event_id, seats_available, timestamp } = event;

    // Create notification object
    const notification = {
      event_id: event_id,
      seats_available: seats_available,
      timestamp: timestamp || new Date().toISOString(),
      alert_type: "LOW_SEATS",
      message: `Event ${event_id} has only ${seats_available} seats remaining!`,
    };

    // Write to S3 bucket
    const key = `notifications/event-${event_id}-${Date.now()}.json`;

    await s3Client.send(
      new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(notification, null, 2),
        ContentType: "application/json",
      }),
    );

    console.log(`Notification written to S3: ${key}`);

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: "Notification saved to S3",
        key: key,
      }),
    };
  } catch (err) {
    console.error("Lambda error:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message,
      }),
    };
  }
};
