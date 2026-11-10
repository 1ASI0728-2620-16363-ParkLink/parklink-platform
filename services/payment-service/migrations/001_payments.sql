CREATE TABLE payments (
 id uuid PRIMARY KEY, attempt_id uuid NOT NULL UNIQUE, reservation_id uuid NOT NULL, driver_id uuid NOT NULL, owner_id uuid NOT NULL,
 amount integer NOT NULL CHECK(amount>0), currency text NOT NULL CHECK(currency='PEN'),
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED','REFUNDED')),
 provider text NOT NULL, reference text, checkout_url text, scenario text NOT NULL, correlation_id uuid NOT NULL,
 lease_until timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX payment_provider_reference ON payments(provider,reference) WHERE reference IS NOT NULL;
CREATE INDEX payment_driver ON payments(driver_id,created_at);
CREATE INDEX payment_owner ON payments(owner_id,created_at);
CREATE TABLE refunds (
 id uuid PRIMARY KEY, payment_id uuid NOT NULL REFERENCES payments(id), operation_key text NOT NULL UNIQUE,
 amount integer NOT NULL CHECK(amount>0), status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','PROCESSED')),
 reference text, lease_until timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
