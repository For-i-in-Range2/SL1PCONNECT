-- db-velvet : schema + jeu de donnees de demonstration
-- (mots de passe stockes en clair : volontaire)

CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    email    TEXT NOT NULL,
    password TEXT NOT NULL,
    role     TEXT NOT NULL DEFAULT 'user'
);

CREATE TABLE health_data (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER REFERENCES users(id),
    heart_rate    INTEGER,
    fall_detected BOOLEAN NOT NULL DEFAULT false,
    posture       TEXT,
    recorded_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO users (email, password, role) VALUES
    ('admin@sl1pconnect.fr',         'admin',        'admin'),
    ('calvin.slipp@sl1pconnect.fr',  'Sl1p2024!',    'admin'),
    ('jean.dupont@example.com',      'password123',  'user'),
    ('marie.martin@example.com',     'azerty',       'user');

INSERT INTO health_data (user_id, heart_rate, fall_detected, posture) VALUES
    (3,  72, false, 'upright'),
    (3, 112, false, 'walking'),
    (4,  65, true,  'lying'),
    (4,  88, false, 'sitting');
