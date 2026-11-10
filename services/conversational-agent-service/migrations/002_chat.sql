CREATE TABLE conversations (
 id uuid PRIMARY KEY,actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours'
);
CREATE INDEX conversations_expiry ON conversations(expires_at);
CREATE TABLE chat_turns (
 id uuid PRIMARY KEY,conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
 actor_id uuid NOT NULL,request_hash text NOT NULL,user_text text NOT NULL,response jsonb,
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','COMPLETE','FAILED')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_actor_recent ON chat_turns(actor_id,created_at);
