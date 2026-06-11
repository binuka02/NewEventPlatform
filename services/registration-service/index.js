const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");
const axios = require("axios");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

async function initDB() {
  try {
    await pool.query(`
            CREATE TABLE IF NOT EXISTS registrations (
                registration_id SERIAL PRIMARY KEY,
                event_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                ticket_count INTEGER NOT NULL DEFAULT 1,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
    console.log("Registrations table ready");
  } catch (err) {
    console.error("DB init error:", err);
  }
}

// Trigger Lambda when seats drop below threshold
async function triggerLowSeatAlert(eventId, seatsAvailable) {
  try {
    const lambdaUrl = process.env.LAMBDA_URL;
    if (!lambdaUrl) {
      console.log("Lambda URL not configured, skipping alert");
      return;
    }
    await axios.post(lambdaUrl, {
      event_id: eventId,
      seats_available: seatsAvailable,
      timestamp: new Date().toISOString(),
    });
    console.log(`Low seat alert triggered for event ${eventId}`);
  } catch (err) {
    console.error("Lambda trigger error:", err.message);
  }
}

// POST /register - Register for an event
app.post("/register", async (req, res) => {
  const { event_id, name, email, ticket_count } = req.body;

  // Validate required fields
  if (!event_id || !name || !email || !ticket_count) {
    return res.status(400).json({
      success: false,
      error: "Missing required fields: event_id, name, email, ticket_count",
    });
  }

  try {
    // Step 1: Save registration
    const registration = await pool.query(
      `INSERT INTO registrations (event_id, name, email, ticket_count)
             VALUES ($1, $2, $3, $4) RETURNING *`,
      [event_id, name, email, ticket_count],
    );

    // Step 2: Update seats in Event Service
    const eventServiceUrl =
      process.env.EVENT_SERVICE_URL || "http://event-service:3001";

    // Get current event details
    const eventResponse = await axios.get(
      `${eventServiceUrl}/events/${event_id}`,
    );
    const event = eventResponse.data.data;

    // Calculate new seats available
    const newSeatsAvailable = event.seats_available - ticket_count;

    if (newSeatsAvailable < 0) {
      return res.status(400).json({
        success: false,
        error: "Not enough seats available",
      });
    }

    // Update seats
    await axios.put(`${eventServiceUrl}/events/${event_id}/seats`, {
      seats_available: newSeatsAvailable,
    });

    // Step 3: Check if seats dropped below threshold (10)
    const LOW_SEAT_THRESHOLD = 10;
    if (newSeatsAvailable < LOW_SEAT_THRESHOLD) {
      console.log(
        `⚠️ Low seats alert! Event ${event_id} has only ${newSeatsAvailable} seats left`,
      );
      await triggerLowSeatAlert(event_id, newSeatsAvailable);
    }

    res.status(201).json({
      success: true,
      message: "Registration successful!",
      data: {
        registration: registration.rows[0],
        seats_remaining: newSeatsAvailable,
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /registrations - List all registrations
app.get("/registrations", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM registrations ORDER BY timestamp DESC",
    );
    res.json({ success: true, data: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /registrations/:eventId - Get registrations for specific event
app.get("/registrations/:eventId", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM registrations WHERE event_id = $1 ORDER BY timestamp DESC",
      [req.params.eventId],
    );
    res.json({ success: true, data: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "registration-service" });
});

const PORT = process.env.PORT || 3003;
app.listen(PORT, async () => {
  console.log(`Registration Service running on port ${PORT}`);
  await initDB();
});
