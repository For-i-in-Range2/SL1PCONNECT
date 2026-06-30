"""
thread-api – version corrigee
Corrections :
  1. debug=False  (plus jamais debug=True en prod)
  2. Secrets lus depuis /run/secrets/ (Docker Secrets)
  3. JWT signe avec HS256 via PyJWT (plus de concatenation triviale)
  4. Mot de passe verifie via bcrypt (plus de plaintext)
"""
import os
import time
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from flask import Flask, request, jsonify
import psycopg2

app = Flask(__name__)

# ------------------------------------------------------------------
# Lecture des secrets Docker (pas d'env vars pour les donnees sensibles)
# ------------------------------------------------------------------

def read_secret(name: str) -> str:
    """Lit un Docker Secret depuis /run/secrets/<name>."""
    try:
        with open(f"/run/secrets/{name}", "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        # Fallback env var pour les tests locaux sans Docker
        return os.environ.get(name.upper(), "")


JWT_SECRET = read_secret("jwt_secret")

DB = dict(
    host=os.environ.get("DB_HOST", "db-velvet"),
    dbname=os.environ.get("DB_NAME", "velvet"),
    user=os.environ.get("DB_USER", "velvet"),
    password=read_secret("db_password"),        # secret, pas d'env var
    port=int(os.environ.get("DB_PORT", "5432")),
)

# ------------------------------------------------------------------
# Connexion DB avec retry
# ------------------------------------------------------------------

def get_db():
    last = None
    for _ in range(15):
        try:
            return psycopg2.connect(**DB)
        except psycopg2.OperationalError as e:
            last = e
            time.sleep(2)
    raise RuntimeError("base indisponible: %s" % last)

# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------

@app.route("/health")
def health():
    return jsonify(status="ok", service="thread-api")


@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json(force=True, silent=True) or {}
    email = data.get("email", "")
    password = data.get("password", "")

    conn = get_db()
    cur = conn.cursor()
    # Correction #4 : on recupere le hash, pas le mot de passe en clair
    cur.execute(
        "SELECT id, password_hash, role FROM users WHERE email = %s",
        (email,),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return jsonify(error="invalid credentials"), 401

    user_id, password_hash, role = row

    # Correction #4 : verification bcrypt — timing safe, pas de comparaison directe
    if not bcrypt.checkpw(password.encode(), password_hash.encode()):
        return jsonify(error="invalid credentials"), 401

    # Correction #3 : JWT signe HS256 avec expiration
    payload = {
        "sub": user_id,
        "role": role,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(hours=8),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    return jsonify(token=token, user_id=user_id, role=role)


@app.route("/api/sensors", methods=["POST"])
def add_sensor():
    # TODO: verifier le JWT avant d'accepter les donnees
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO health_data (user_id, heart_rate, fall_detected, posture) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (data.get("user_id"), data.get("heart_rate"),
         data.get("fall_detected", False), data.get("posture")),
    )
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(id=new_id, status="recorded")


@app.route("/api/sensors/<int:user_id>")
def get_sensors(user_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, heart_rate, fall_detected, posture, recorded_at "
        "FROM health_data WHERE user_id = %s ORDER BY id",
        (user_id,),
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([
        dict(id=r[0], heart_rate=r[1], fall_detected=r[2],
             posture=r[3], recorded_at=str(r[4]))
        for r in rows
    ])


if __name__ == "__main__":
    # Correction #1 : debug=False, bind sur 0.0.0.0 (Gunicorn gere le prod)
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8080")),
        debug=False,   # JAMAIS True en production
    )
