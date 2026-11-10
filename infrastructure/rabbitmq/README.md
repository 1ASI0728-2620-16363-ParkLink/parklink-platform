# Command broker and event bus

The broker is independent from the Gateway. `packages/runtime/src/messaging.ts` declares durable topology before any outbox relay starts, including consumers that are currently offline. This prevents an initial publication from disappearing because a downstream process has not started yet.

| Exchange | Queue | Bindings |
|---|---|---|
| parklink.commands.v1 | reservation.commands.v1 | reservation.*.v1 |
| parklink.commands.v1 | payment.commands.v1 | payment.*.v1 |
| parklink.events.v1 | reservation.events.v1 | supply.revision-proposed.v1, payment.authorized.v1, payment.failed.v1 |
| parklink.events.v1 | supply.events.v1 | supply.revision-accepted.v1, supply.revision-rejected.v1 |
| parklink.events.v1 | discovery.events.v1 | supply.revision-accepted.v1, reservation.*.v1 |
| parklink.events.v1 | notification.events.v1 | confirmed, cancelled, expired, payment-failed and refund events |
| parklink.events.v1 | audit.events.v1 | # |

All primary, retry and dead queues are quorum queues. Every primary queue has `.retry` (3-second TTL) and `.dlq` companions. A failed handler republishes persistently to retry and waits for publisher confirmation before acknowledging the original. At most three application retries are attempted; exhausted messages are dead-lettered to `parklink.dead.v1`. Broker failures leave the original unacknowledged. Reconnection redeclares compatible topology. Consumers ack only after their local transaction commits; inbox primary keys deduplicate replay. Outbox rows are marked published only after broker confirmation; a crash can republish the same ID safely.

At-least-once SQL/AMQP handling is NOT exactly-once transport. Production must additionally configure RabbitMQ quorum at-least-once dead-lettering and `overflow=reject-publish` policies, capacity alerts and publisher timeout limits. A single-node local quorum queue provides persistence but not high availability; use the three-node operator manifest in production.

Inspect queues: `docker compose exec rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged`. Investigate DLQs before replay. Preserve message IDs, actor and correlation IDs, and replay into the original primary queue after fixing the handler. Never turn a failed command into a fake confirmed event. Pending operations corresponding to exhausted messages require operator intervention; an automated terminal-status reconciliation worker is not implemented yet.

Local development shares a broker credential so each process can declare topology. Production needs separate broker users, scoped exchange/queue permissions and a topology provisioning job before narrowing configure permissions. Use AMQPS and trusted certificates. Local management is bound only to loopback port 15672.
