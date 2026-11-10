# Imágenes independientes

Cada servicio tiene su propio Dockerfile. Las compilaciones copian el código compartido de transporte y ejecución, y únicamente el servicio seleccionado; nunca incluyen las implementaciones de otros servicios. Ejecute desde la raíz del proyecto: `sh scripts/image.sh reservation-service registry.example.com/parklink your-commit-tag`.

Las imágenes locales usan Node 22 Alpine, una etapa de compilación, dependencias de producción depuradas y un usuario sin privilegios de administrador durante la ejecución. Incluyen código fuente y mapas de origen para diagnóstico; elimínelos posteriormente si la política de seguridad de los artefactos lo requiere. Las imágenes no se publican automáticamente. El archivo `.dockerignore` de la raíz excluye secretos, metadatos Git, fuentes móviles y recursos del informe de los contextos de imagen del backend.
