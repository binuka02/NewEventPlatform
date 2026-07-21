const express = require("express");
const cors = require("cors");
require("dotenv").config();
const { createClient } = require("@clickhouse/client");

const app = express();
app.use(cors());
app.use(express.json());

// ClickHouse connection
const clickhouse = createClient({
  url: process.env.CLICKHOUSE_HOST || "http://clickhouse-service:8123",
  username: process.env.CLICKHOUSE_USER || "default",
  password: process.env.CLICKHOUSE_PASSWORD || "",
  database: process.env.CLICKHOUSE_DB || "analytics",
  keep_alive: { enabled: false },
});

// Initialize ClickHouse database and table
async function initClickHouse() {
  try {
    // Create database
    await clickhouse.exec({
      query: `CREATE DATABASE IF NOT EXISTS analytics`,
    });

    // Create web events table
    await clickhouse.exec({
      query: `
                CREATE TABLE IF NOT EXISTS analytics.web_events (
                    event_type String,
                    session_id String,
                    timestamp DateTime,
                    page_url String,
                    user_agent String,
                    section_name String DEFAULT '',
                    speaker_name String DEFAULT '',
                    track_name String DEFAULT '',
                    has_name UInt8 DEFAULT 0,
                    has_email UInt8 DEFAULT 0,
                    referrer String DEFAULT '',
                    screen_width UInt16 DEFAULT 0,
                    screen_height UInt16 DEFAULT 0,
                    extra String DEFAULT ''
                ) ENGINE = MergeTree()
                ORDER BY (timestamp, event_type, session_id)
            `,
    });
    console.log("ClickHouse tables ready");
  } catch (err) {
    console.error("ClickHouse init error:", err.message);
  }
}

// POST /analytics - Receive analytics event from frontend
app.post("/analytics", async (req, res) => {
  try {
    if (!req.body || Object.keys(req.body).length === 0) {
      return res
        .status(400)
        .json({ success: false, error: "Empty request body" });
    }
    const {
      event_type,
      session_id,
      timestamp,
      page_url,
      user_agent,
      section_name,
      speaker_name,
      track_name,
      has_name,
      has_email,
      referrer,
      screen_width,
      screen_height,
      ...extra
    } = req.body;

    // Insert into ClickHouse
    await clickhouse.insert({
      table: "analytics.web_events",
      values: [
        {
          event_type: event_type || "unknown",
          session_id: session_id || "",
          timestamp: timestamp
            ? new Date(timestamp)
                .toISOString()
                .replace("T", " ")
                .substring(0, 19)
            : new Date().toISOString().replace("T", " ").substring(0, 19),
          page_url: page_url || "",
          user_agent: user_agent || "",
          section_name: section_name || "",
          speaker_name: speaker_name || "",
          track_name: track_name || "",
          has_name: has_name ? 1 : 0,
          has_email: has_email ? 1 : 0,
          referrer: referrer || "",
          screen_width: screen_width || 0,
          screen_height: screen_height || 0,
          extra: JSON.stringify(extra),
        },
      ],
      format: "JSONEachRow",
    });

    res.json({ success: true, message: "Event tracked" });
  } catch (err) {
    console.error("Analytics insert error:", err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /analytics/summary - Get analytics summary
app.get("/analytics/summary", async (req, res) => {
  try {
    const result = await clickhouse.query({
      query: `
                SELECT 
                    event_type,
                    count() as count,
                    max(timestamp) as last_seen
                FROM analytics.web_events
                GROUP BY event_type
                ORDER BY count DESC
            `,
      format: "JSONEachRow",
    });
    const data = await result.json();
    res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "analytics-collector" });
});

const PORT = process.env.PORT || 3004;
app.listen(PORT, async () => {
  console.log(`Analytics Collector running on port ${PORT}`);
  await initClickHouse();
});

const server = app.listen(PORT, async () => {
  console.log(`Analytics Collector running on port ${PORT}`);
  await initClickHouse();
});

process.on("SIGTERM", () => {
  console.log("SIGTERM received, shutting down gracefully");
  server.close(() => {
    console.log("Server closed, exiting");
    process.exit(0);
  });
});
