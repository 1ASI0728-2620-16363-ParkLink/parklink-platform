# Reproducible local demo data

Run `node scripts/seed-rich.mjs` after the Compose stack is healthy. This command is restricted to loopback endpoints and refuses production. It does not reset databases, delete existing data or change another user's password.

The seed creates 15 accounts, 60 explicitly fictitious spaces in six Lima districts, 100 historical/active/expired reservation fixtures and 36 future reservations through the real HTTP/RabbitMQ/payment saga. Historical financial records are clearly sandbox fixtures; no bank/provider call is made. Current counts can grow when integration tests or manual operations add records.

Account passwords are generated randomly and kept in `.local/demo-accounts.json` with mode 0600, inside a mode-0700 directory. The directory is ignored by Git and Docker build contexts. The primary client's email is `cliente@parklink.test`. Credentials are for this local development instance only; never reuse them outside the local demo.

Reruns reuse stored account credentials, publication identifiers, booking idempotency keys and historical fixture IDs. Public APIs create users/offers/future workflows. Two explicit development-only import scripts run separately inside their owning Reservation and Payment service containers for historical states that cannot legitimately be created through a present-time booking API. They validate their input, refuse production, preserve database ownership, and use local outboxes to populate Discovery/Audit projections.

Example locations are synthetic, not listings available to the public. The seed leaves PostgreSQL exclusion constraints in force, including for active fixture reservations. Approved, rejected, refunded and pending sandbox states are deliberately distinguishable.
