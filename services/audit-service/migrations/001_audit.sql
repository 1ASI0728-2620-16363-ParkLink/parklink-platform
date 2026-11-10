CREATE TABLE audit_events(id uuid PRIMARY KEY,actor_id uuid NOT NULL,correlation_id uuid NOT NULL,type text NOT NULL,payload jsonb NOT NULL,occurred_at timestamptz NOT NULL,received_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX audit_correlation ON audit_events(correlation_id,occurred_at);
CREATE FUNCTION reject_audit_change() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Audit evidence is append-only'; END $$;
CREATE TRIGGER audit_no_mutation BEFORE UPDATE OR DELETE OR TRUNCATE ON audit_events FOR EACH STATEMENT EXECUTE FUNCTION reject_audit_change();
