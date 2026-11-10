# Intermediario de comandos y bus de eventos

El intermediario es independiente de la pasarela. `packages/runtime/src/messaging.ts` declara una topología duradera antes de iniciar la publicación de la bandeja de salida, incluidas las colas cuyos consumidores estén desconectados. Esto evita que una publicación inicial desaparezca porque un proceso consumidor aún no se ha iniciado.

| Intercambio | Cola | Claves de enlace |
|---|---|---|
| parklink.commands.v1 | reservation.commands.v1 | reservation.*.v1 |
| parklink.commands.v1 | payment.commands.v1 | payment.*.v1 |
| parklink.events.v1 | reservation.events.v1 | supply.revision-proposed.v1, payment.authorized.v1, payment.failed.v1 |
| parklink.events.v1 | supply.events.v1 | supply.revision-accepted.v1, supply.revision-rejected.v1 |
| parklink.events.v1 | discovery.events.v1 | supply.revision-accepted.v1, reservation.*.v1 |
| parklink.events.v1 | notification.events.v1 | Eventos de confirmación, cancelación, caducidad, fallo de pago y reembolso |
| parklink.events.v1 | audit.events.v1 | # |

Todas las colas principales, de reintento y de mensajes fallidos son de tipo cuórum. Cada cola principal tiene una cola `.retry` con vencimiento de tres segundos y una cola `.dlq`. Cuando falla un manejador, el mensaje se publica de forma persistente en la cola de reintento y se espera la confirmación del intermediario antes de confirmar el original. Se realizan hasta tres reintentos de aplicación; los mensajes que los agotan se envían a `parklink.dead.v1`. Si falla el intermediario, el mensaje original queda sin confirmar. Al reconectar se vuelve a declarar la topología compatible.

Los consumidores confirman los mensajes después de completar su transacción local; las claves de la bandeja de entrada permiten detectar repeticiones. Los registros de la bandeja de salida se marcan como publicados después de la confirmación del intermediario. Una caída puede provocar la republicación del mismo identificador, que debe procesarse de forma idempotente.

El procesamiento SQL/AMQP con entrega al menos una vez **no equivale a transporte exactamente una vez**. En producción también se deben configurar el envío de mensajes fallidos de cuórum con entrega al menos una vez, las políticas `overflow=reject-publish`, alertas de capacidad y límites de espera para publicación. Una cola de cuórum en un solo nodo local proporciona persistencia, pero no alta disponibilidad; para producción utilice el manifiesto del operador con tres nodos.

Para inspeccionar las colas: `docker compose exec rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged`. Investigue las colas de mensajes fallidos antes de reprocesarlos. Después de corregir el manejador, conserve los identificadores del mensaje, actor y correlación y reenvíe el mensaje a la cola principal original. Nunca convierta un comando fallido en un evento de confirmación ficticio. Las operaciones pendientes asociadas a mensajes que agotaron los reintentos requieren intervención de un operador; aún no existe un proceso automático de conciliación de estados terminales.

En desarrollo local se comparte una credencial del intermediario para que cada proceso pueda declarar la topología. En producción se necesitan usuarios separados, permisos limitados por intercambio y cola, y una tarea de aprovisionamiento de la topología antes de restringir los permisos de configuración. Use AMQPS y certificados confiables. La administración local solo escucha en la interfaz de retorno local, puerto 15672.
