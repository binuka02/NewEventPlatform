const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());

// PostgreSQL connection using Kubernetes secrets
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

// Create events table if it doesn't exist
async function initDB() {
  try {
    await pool.query(`
            CREATE TABLE IF NOT EXISTS events (
                event_id SERIAL PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                venue VARCHAR(255) NOT NULL,
                event_date TIMESTAMP NOT NULL,
                ticket_price DECIMAL(10,2) NOT NULL,
                capacity INTEGER NOT NULL,
                seats_available INTEGER NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
    console.log("Events table ready");

    // Insert sample data if table is empty
    const count = await pool.query("SELECT COUNT(*) FROM events");
    if (parseInt(count.rows[0].count) === 0) {
      await pool.query(`
                INSERT INTO events (title, venue, event_date, ticket_price, capacity, seats_available)
                VALUES 
                ('Cloud Computing Summit 2026', 'Colombo Convention Centre', '2026-09-15 09:00:00', 2500.00, 500, 487),
                ('DevOps Workshop 2026', 'IIT Auditorium', '2026-10-01 10:00:00', 1500.00, 200, 145)
            `);
      console.log("Sample events inserted");
    }
  } catch (err) {
    console.error("DB init error:", err);
  }
}

// ============================================
// ROUTES
// ============================================

// GET /events - List all events
// Includes a "version" marker so a blue-green switch is provable via the API
// response, not just by checking which colour the Service selector points to
app.get("/events", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM events ORDER BY event_date ASC",
    );
    res.json({
      success: true,
      version: "blue-green-test",
      data: result.rows,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /events/:id - Get single event
app.get("/events/:id", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM events WHERE event_id = $1",
      [req.params.id],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: "Event not found" });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /events - Create new event
app.post("/events", async (req, res) => {
  const { title, venue, event_date, ticket_price, capacity, seats_available } =
    req.body;
  try {
    const result = await pool.query(
      `INSERT INTO events (title, venue, event_date, ticket_price, capacity, seats_available)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [title, venue, event_date, ticket_price, capacity, seats_available],
    );
    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// PUT /events/:id/seats - Update seats available
app.put("/events/:id/seats", async (req, res) => {
  const { seats_available } = req.body;
  try {
    const result = await pool.query(
      `UPDATE events SET seats_available = $1 
             WHERE event_id = $2 RETURNING *`,
      [seats_available, req.params.id],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: "Event not found" });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Health check endpoint (used by Kubernetes)
app.get("/health", (req, res) => {
  res.json({
    status: "healthy",
    service: "event-service",
    version: "blue-green-test",
  });
});

// Start server
const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, async () => {
  console.log(`Event Service running on port ${PORT}`);
  await initDB();
});

process.on("SIGTERM", () => {
  console.log("SIGTERM received, shutting down gracefully");
  server.close(() => {
    pool.end(() => {
      console.log("DB pool closed, exiting");
      process.exit(0);
    });
  });
});
