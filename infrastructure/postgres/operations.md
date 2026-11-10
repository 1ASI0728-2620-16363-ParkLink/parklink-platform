# Independent database operations

Compose runs eight separate PostgreSQL containers, eight roles/passwords and eight volumes. Discovery alone enables PostGIS; Reservation enables btree_gist. Extensions must be provisioned by the managed database administrator before running migrations with a least-privilege deployment role.

Migrations run under a per-database advisory lock, in a transaction, with SHA-256 checksums. Editing an applied migration is rejected; add a new numbered SQL file instead. Each service supports `node dist/main.js --migrate`. Production Helm runs a pre-install/pre-upgrade migration Job. Runtime startup also checks migrations, so database credentials currently need DDL privileges: split runtime and migration roles before production approval.

For production use one independent managed database and credential per service, TLS (`sslmode=verify-full` with trusted CA), PITR/WAL archiving, encrypted daily snapshots and a tested restoration procedure. Set explicit RPO/RTO with the platform owner. No cross-database joins, foreign keys or backup restore coupling.

Local logical backup example: `docker compose exec -T reservation-db pg_dump -U reservation -d reservation -Fc > reservation.dump`. Back up every other database separately. Backups contain personal data; encrypt, restrict and expire them. Never delete volumes as an upgrade procedure. Test restoration into a separate non-production database before relying on a backup.
