#!/usr/bin/env sh
set -eu
name=${1:?Usage: sh scripts/image.sh service-name registry/parklink immutable-tag}
registry=${2:?Specify registry path}
tag=${3:?Specify immutable tag}
case "$name" in
  gateway) dockerfile=gateway/Dockerfile ;;
  owner-dashboard) dockerfile=apps/owner-dashboard/Dockerfile ;;
  identity-service|parking-supply-service|parking-discovery-service|reservation-service|payment-service|notification-service|conversational-agent-service|audit-service) dockerfile="services/$name/Dockerfile" ;;
  *) exit 2 ;;
esac
docker build -f "$dockerfile" -t "$registry/$name:$tag" .
# Deliberately does not push images or deploy anything.
