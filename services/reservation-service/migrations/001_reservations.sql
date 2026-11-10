CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE space_snapshots (id uuid PRIMARY KEY, owner_id uuid NOT NULL, revision integer NOT NULL, body jsonb NOT NULL);
CREATE TABLE reservations (
 id uuid PRIMARY KEY, space_id uuid NOT NULL REFERENCES space_snapshots(id), driver_id uuid NOT NULL, owner_id uuid NOT NULL,
 start_time timestamptz NOT NULL, end_time timestamptz NOT NULL, amount integer NOT NULL CHECK(amount>0),
 currency text NOT NULL DEFAULT 'PEN' CHECK(currency='PEN'), hourly_rate integer NOT NULL,
 supply_revision integer NOT NULL, status text NOT NULL CHECK(status IN ('PENDING_PAYMENT','CONFIRMED','ACTIVE','COMPLETED','CANCELLED','EXPIRED')),
 expires_at timestamptz NOT NULL, payment_id uuid, payment_attempt uuid, code text NOT NULL UNIQUE,
 version integer NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(), CHECK(start_time<end_time),
 EXCLUDE USING gist (space_id WITH =, tstzrange(start_time,end_time,'[)') WITH &&)
   WHERE (status IN ('PENDING_PAYMENT','CONFIRMED','ACTIVE'))
);
CREATE INDEX reservations_driver ON reservations(driver_id,start_time);
CREATE INDEX reservations_owner ON reservations(owner_id,start_time);
CREATE INDEX reservations_expiry ON reservations(expires_at) WHERE status='PENDING_PAYMENT';
CREATE TABLE operations (
 id uuid PRIMARY KEY, actor_id uuid NOT NULL, kind text NOT NULL, key text NOT NULL,
 hash text NOT NULL, status text NOT NULL DEFAULT 'PENDING', result jsonb, http_status integer,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(actor_id,kind,key)
);
CREATE TABLE reservation_history (id bigserial PRIMARY KEY, reservation_id uuid NOT NULL REFERENCES reservations(id), status text NOT NULL, correlation_id uuid NOT NULL, at timestamptz NOT NULL DEFAULT now());
