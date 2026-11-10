CREATE TABLE spaces (
 id uuid PRIMARY KEY, owner_id uuid NOT NULL, revision integer NOT NULL CHECK(revision>0),
 accepted_revision integer NOT NULL DEFAULT 0, body jsonb NOT NULL,
 state text NOT NULL CHECK(state IN ('REVIEWING','PUBLISHED','REJECTED')), rejection text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX spaces_owner ON spaces(owner_id);
