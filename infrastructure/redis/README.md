# Alcance de Redis

Redis está aprovisionado con AOF y un volumen independiente para una futura caché descartable de búsqueda o conversación. Los manejadores actuales de la aplicación no lo utilizan y no es la autoridad de las reservas. Su eliminación no debe alterar la corrección de las reservas. En producción, Redis necesita una red privada, credenciales ACL y TLS; no exponga la instancia local sin protección.
