# Independent images

Every service has its own Dockerfile. Builds copy shared transport/runtime code and only the selected service, never other service implementations. Run from the project root: `sh scripts/image.sh reservation-service registry.example.com/parklink your-commit-tag`.

Local images use Node 22 Alpine, a build stage, pruned production dependencies and a non-root runtime. Images include source and source maps for diagnostics; strip these in a later hardened artifact policy if required. No image push is automatic. Root `.dockerignore` excludes secrets, original Git metadata, mobile sources and report assets from backend image contexts.
