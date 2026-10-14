#!/usr/bin/env bash
# Pulihkan backup mLITE Rizki Medika.
#   sudo bash restore.sh /var/backups/mlite/harian/mlite-2026-10-14.tar.gz.gpg
# (ambil dulu dari offsite bila server baru: rclone copy <remote>/harian/<file> /var/backups/mlite/harian/)
# PERINGATAN: database & folder uploads saat ini akan DITIMPA.
set -euo pipefail
cd "$(dirname "$0")"
FILE=${1:?"pakai: restore.sh <file.tar.gz.gpg>"}
ENV_FILE=.env.production
set -a; . "./$ENV_FILE"; set +a
COMPOSE=(docker compose -p mlite -f docker-compose.yaml -f docker-compose.prod.yaml --env-file "$ENV_FILE")

read -r -p "Timpa database '${DB_DATABASE}' dan uploads dengan $(basename "$FILE")? ketik YA: " OK
[ "$OK" = "YA" ] || { echo "dibatalkan"; exit 1; }

KERJA=$(mktemp -d)
trap 'rm -rf "$KERJA"' EXIT
gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" -d "$FILE" | tar -C "$KERJA" -xzf -

echo "== database"
"${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" \
  -e "DROP DATABASE IF EXISTS \`${DB_DATABASE}\`; CREATE DATABASE \`${DB_DATABASE}\` CHARACTER SET utf8mb4; GRANT ALL ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'%';"
"${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" "$DB_DATABASE" < "$KERJA/database.sql"

echo "== uploads"
"${COMPOSE[@]}" exec -T php sh -c 'rm -rf /var/www/html/uploads/* && tar -C /var/www/html -xzf - && chown -R www-data:www-data /var/www/html/uploads' < "$KERJA/uploads.tar.gz"

echo "Selesai. Cek https://${DOMAIN}/admin"
