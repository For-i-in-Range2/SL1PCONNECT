import os
import time
from flask import Flask, request, jsonify
import psycopg2

app = Flask(__name__)

# secret en clair
JWT_SECRET = os.environ.get("JWT_SECRET", "sl1p-super-secret-key-2024")

DB = dict(
    host=os.environ.get("DB_HOST", "db-velvet"),
    dbname=os.environ.get("DB_NAME", "velvet"),
    user=os.environ.get("DB_USER", "velvet"),
    password=os.environ.get("DB_PASSWORD", "velvet"),
    port=int(os.environ.get("DB_PORT", "5432")),
)


def get_db():
    # petite boucle de retry : postgres peut demarrer apres l'api
    last = None
    for _ in range(15):
        try:
            return psycopg2.connect(**DB)
        except psycopg2.OperationalError as e:
            last = e
            time.sleep(2)
    raise RuntimeError("base indisponible: %s" % last)


@app.route("/health")
def health():
    return jsonify(status="ok", service="thread-api")


@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, role FROM users WHERE email=%s AND password=%s",
        (data.get("email", ""), data.get("password", "")),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        return jsonify(error="invalid credentials"), 401
    # "token" trivial, non signe (volontaire)
    return jsonify(token="%s.%s" % (row[0], JWT_SECRET), user_id=row[0], role=row[1])


@app.route("/api/sensors", methods=["POST"])
def add_sensor():
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
        "FROM health_data WHERE user_id=%s ORDER BY id",
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
    # debug active + bind sur toutes les interfaces (volontaire)
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), debug=True)
