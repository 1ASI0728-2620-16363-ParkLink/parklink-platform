CREATE EXTENSION IF NOT EXISTS postgis;
CREATE TABLE space_documents (id uuid PRIMARY KEY, revision integer NOT NULL, body jsonb NOT NULL, location geography(Point,4326) NOT NULL, updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX discovery_geo ON space_documents USING gist(location);
CREATE TABLE reservation_windows (id uuid PRIMARY KEY, space_id uuid NOT NULL, version integer NOT NULL, start_time timestamptz NOT NULL, end_time timestamptz NOT NULL, status text NOT NULL, expires_at timestamptz NOT NULL);
CREATE INDEX discovery_windows ON reservation_windows(space_id,start_time,end_time);
