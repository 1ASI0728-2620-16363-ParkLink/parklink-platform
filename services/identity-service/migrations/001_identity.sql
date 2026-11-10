CREATE TABLE users (
 id uuid PRIMARY KEY, email text NOT NULL UNIQUE, name text NOT NULL,
 password_hash text NOT NULL, roles text[] NOT NULL DEFAULT '{DRIVER}',
 created_at timestamptz NOT NULL DEFAULT now(), CHECK(email=lower(email))
);
