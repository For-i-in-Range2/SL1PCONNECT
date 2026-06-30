-- db-velvet : schema + donnees de demonstration
-- Correction : mots de passe stockes en hash bcrypt (plus jamais en clair)
-- Les hashes ont ete generes avec bcrypt.hashpw(..., bcrypt.gensalt(12))

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,        -- HASH bcrypt, jamais le mot de passe
    role          TEXT NOT NULL DEFAULT 'user'
);

CREATE TABLE IF NOT EXISTS health_data (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER REFERENCES users(id) ON DELETE CASCADE,
    heart_rate    INTEGER,
    fall_detected BOOLEAN NOT NULL DEFAULT false,
    posture       TEXT,
    recorded_at   TIMESTAMP NOT NULL DEFAULT now()
);

-- Mots de passe de demo (hash bcrypt, cout 12) :
--   admin@sl1pconnect.fr      -> 'admin'       (changer en prod !)
--   calvin.slipp@sl1pconnect.fr -> 'Sl1p2024!'
--   jean.dupont@example.com   -> 'password123'
--   marie.martin@example.com  -> 'azerty'

INSERT INTO users (email, password_hash, role) VALUES
    ('admin@sl1pconnect.fr',
     '$2b$12$kU.BduPJyd4F7mpDJubjie8z0xG.Me/yr/e3xX2Jcp192aP2Ej1qS',
     'admin'),
    ('calvin.slipp@sl1pconnect.fr',
     '$2b$12$2eCwMKZsoT111G1JEGWka.ChQQD6KzDOXrk667.bo.K0Cv4xSyNLK',
     'admin'),
    ('jean.dupont@example.com',
     '$2b$12$APRKMLAH5lNRIt3QaZ/ObOyKjhqk2qoU7WvCCBmgxZlnce3gOToAu',
     'user'),
    ('marie.martin@example.com',
     '$2b$12$jhJkvlXcoYaWXUumFQduCu3f2Chqv.3e9gT3jYWFsHao1s46egcwa',
     'user')
ON CONFLICT (email) DO NOTHING;

INSERT INTO health_data (user_id, heart_rate, fall_detected, posture) VALUES
    (3,  72, false, 'upright'),
    (3, 112, false, 'walking'),
    (4,  65, true,  'lying'),
    (4,  88, false, 'sitting');
