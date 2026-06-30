"use strict";
/**
 * stitch-processor – version corrigee
 * Corrections :
 *   1. Mot de passe DB lu depuis /run/secrets/ (Docker Secret)
 *   2. Dependances a jour (express 4.21, pg 8.x)
 */
const fs      = require("fs");
const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());

// ── Lecture des secrets Docker ────────────────────────────────────
function readSecret(name) {
  try {
    return fs.readFileSync(`/run/secrets/${name}`, "utf8").trim();
  } catch {
    // Fallback pour tests locaux sans Docker Secrets
    return process.env[name.toUpperCase()] || "";
  }
}

// Correction #1 : mot de passe depuis le secret, pas l'env var
const pool = new Pool({
  host:     process.env.DB_HOST     || "db-velvet",
  database: process.env.DB_NAME     || "velvet",
  user:     process.env.DB_USER     || "velvet",
  password: readSecret("db_password"),
  port:     parseInt(process.env.DB_PORT || "5432", 10),
});

// ── Routes ────────────────────────────────────────────────────────

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "stitch-processor" });
});

// Traitement des donnees de sante : calcul du score de risque
app.get("/process", async (_req, res) => {
  try {
    const r = await pool.query(
      "SELECT user_id, heart_rate, fall_detected, posture FROM health_data ORDER BY id"
    );
    const out = r.rows.map((row) => {
      let risk = 0;
      if (row.fall_detected)                              risk += 50;
      if (row.heart_rate > 100 || row.heart_rate < 50)   risk += 30;
      if (row.posture === "lying")                        risk += 20;
      return { user_id: row.user_id, risk_score: risk, alert: risk >= 50 };
    });
    res.json(out);
  } catch (e) {
    // Ne jamais exposer le message d'erreur interne au client
    console.error("process error:", e.message);
    res.status(500).json({ error: "internal server error" });
  }
});

app.get("/stats", async (_req, res) => {
  try {
    const r = await pool.query("SELECT count(*)::int AS total FROM health_data");
    res.json({ total_records: r.rows[0].total });
  } catch (e) {
    console.error("stats error:", e.message);
    res.status(500).json({ error: "internal server error" });
  }
});

const PORT = parseInt(process.env.PORT || "8082", 10);
app.listen(PORT, "0.0.0.0", () =>
  console.log(`stitch-processor listening on port ${PORT}`)
);
