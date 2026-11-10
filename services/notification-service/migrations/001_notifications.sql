CREATE TABLE preferences(user_id uuid PRIMARY KEY,in_app boolean NOT NULL DEFAULT true);
CREATE TABLE notifications(id uuid PRIMARY KEY,user_id uuid NOT NULL,event_id uuid NOT NULL,type text NOT NULL,body jsonb NOT NULL,read_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,event_id));
CREATE INDEX notifications_user ON notifications(user_id,created_at);
