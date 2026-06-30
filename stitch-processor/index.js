const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());

// secrets BDD en clair
const pool = new Pool({
  host: process.env.DB_HOST || "db-velvet",
  database: process.env.DB_NAME || "velvet",
  user: process.env.DB_USER || "velvet",
  password: process.env.DB_PASSWORD || "velvet",
  port: parseInt(process.env.DB_PORT || "5432", 10),
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "stitch-processor" });
});

// "traitement" des donnees de sante : score de risque trivial
app.get("/process", async (req, res) => {
  try {
    const r = await pool.query(
      "SELECT user_id, heart_rate, fall_detected, posture FROM health_data ORDER BY id"
    );
    const out = r.rows.map((row) => {
      let risk = 0;
      if (row.fall_detected) risk += 50;
      if (row.heart_rate > 100 || row.heart_rate < 50) risk += 30;
      if (row.posture === "lying") risk += 20;
      return { user_id: row.user_id, risk_score: risk, alert: risk >= 50 };
    });
    res.json(out);
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

app.get("/stats", async (req, res) => {
  try {
    const r = await pool.query("SELECT count(*)::int AS total FROM health_data");
    res.json({ total_records: r.rows[0].total });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

const PORT = parseInt(process.env.PORT || "8082", 10);
app.listen(PORT, "0.0.0.0", () => console.log("stitch-processor on " + PORT));
