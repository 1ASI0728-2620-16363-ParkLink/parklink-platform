CREATE TABLE confirmations(id uuid PRIMARY KEY,actor_id uuid NOT NULL,payload jsonb NOT NULL,summary jsonb NOT NULL,expires_at timestamptz NOT NULL,consumed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX confirmations_expiry ON confirmations(expires_at);
