#!/usr/bin/env sh
set -eu
mkdir -p backups
STAMP=$(date +%Y%m%d-%H%M%S)
docker compose exec -T postgres pg_dump -U goldbrain -d goldbrain -Fc > "backups/goldbrain-$STAMP.dump"
echo "Created backups/goldbrain-$STAMP.dump"
