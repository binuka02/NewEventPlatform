const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");
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
            CREATE TABLE IF NOT EXISTS programs (
                program_id SERIAL PRIMARY KEY,
                event_id INTEGER NOT NULL,
                day INTEGER NOT NULL,
                track VARCHAR(255) NOT NULL,
                session_name VARCHAR(255) NOT NULL,
                speaker_name VARCHAR(255) NOT NULL,
                start_time TIME NOT NULL,
                end_time TIME NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
    console.log("Programs table ready");

    const count = await pool.query("SELECT COUNT(*) FROM programs");
    if (parseInt(count.rows[0].count) === 0) {
      await pool.query(`
                INSERT INTO programs (event_id, day, track, session_name, speaker_name, start_time, end_time)
                VALUES
                (1, 1, 'Cloud Computing Track', 'Introduction to AWS EKS', 'Dr. John Smith', '09:00', '10:00'),
                (1, 1, 'Cloud Computing Track', 'Kubernetes Best Practices', 'Jane Doe', '10:00', '11:00'),
                (1, 1, 'DevOps Track', 'CI/CD Pipeline Design', 'Mike Johnson', '11:00', '12:00'),
                (1, 2, 'Security Track', 'Cloud Security Fundamentals', 'Sarah Connor', '09:00', '10:30'),
                (1, 2, 'DevOps Track', 'Docker and Containerization', 'Tom Wilson', '10:30', '12:00')
            `);
      console.log("Sample programs inserted");
    }
  } catch (err) {
    console.error("DB init error:", err);
  }
}

// GET /programs - List all programs
app.get("/programs", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM programs ORDER BY day ASC, start_time ASC",
    );
    res.json({ success: true, data: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /programs/:eventId - Get programs for specific event
app.get("/programs/:eventId", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM programs WHERE event_id = $1 ORDER BY day ASC, start_time ASC",
      [req.params.eventId],
    );
    res.json({ success: true, data: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /programs - Create new program
app.post("/programs", async (req, res) => {
  const {
    event_id,
    day,
    track,
    session_name,
    speaker_name,
    start_time,
    end_time,
  } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO programs (event_id, day, track, session_name, speaker_name, start_time, end_time)
             VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [event_id, day, track, session_name, speaker_name, start_time, end_time],
    );
    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "program-service" });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, async () => {
  console.log(`Program Service running on port ${PORT}`);
  await initDB();
});
