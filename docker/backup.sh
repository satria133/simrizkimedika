#!/usr/bin/env bash
# Backup harian mLITE Rizki Medika: database + uploads -> terenkripsi -> lokal & offsite (rclone).
# Retensi: 7 harian, 4 mingguan (Minggu), 12 bulanan (tanggal 1).
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE=.env.production
set -a; . "./$ENV_FILE"; set +a
COMPOSE=(docker compose -p mlite -f docker-compose.yaml -f docker-compose.prod.yaml --env-file "$ENV_FILE")

DIR=/var/backups/mlite
mkdir -p "$DIR"/{harian,mingguan,bulanan}
chmod 700 "$DIR"
TGL=$(date +%F)
NAMA="mlite-${TGL}"
KERJA=$(mktemp -d)
trap 'rm -rf "$KERJA"' EXIT

echo "[$(date '+%F %T')] mulai backup $NAMA"

# 1) database (konsisten tanpa mengunci tabel InnoDB)
"${COMPOSE[@]}" exec -T mysql mysqldump -uroot -p"$DB_ROOT_PASSWORD" \
  --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 \
  "$DB_DATABASE" > "$KERJA/database.sql"

# 2) berkas unggahan (foto, scan, berkas digital)
"${COMPOSE[@]}" exec -T php tar -C /var/www/html -czf - uploads > "$KERJA/uploads.tar.gz"

# 3) bungkus + enkripsi simetris (AES256)
tar -C "$KERJA" -czf - database.sql uploads.tar.gz \
  | gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" \
        --symmetric --cipher-algo AES256 -o "$DIR/harian/$NAMA.tar.gz.gpg"

[ "$(date +%u)" = 7 ] && cp "$DIR/harian/$NAMA.tar.gz.gpg" "$DIR/mingguan/"
[ "$(date +%d)" = 01 ] && cp "$DIR/harian/$NAMA.tar.gz.gpg" "$DIR/bulanan/"

# 4) retensi lokal
ls -1t "$DIR/harian"/*.gpg   2>/dev/null | tail -n +8  | xargs -r rm -f
ls -1t "$DIR/mingguan"/*.gpg 2>/dev/null | tail -n +5  | xargs -r rm -f
ls -1t "$DIR/bulanan"/*.gpg  2>/dev/null | tail -n +13 | xargs -r rm -f

# 5) offsite: cerminkan folder backup ke object storage
if [ -n "${BACKUP_REMOTE:-}" ] && command -v rclone >/dev/null; then
  rclone sync "$DIR" "$BACKUP_REMOTE" --transfers 2
  echo "[$(date '+%F %T')] offsite OK -> $BACKUP_REMOTE"
else
  echo "[$(date '+%F %T')] PERINGATAN: BACKUP_REMOTE/rclone belum siap, backup hanya lokal"
fi

echo "[$(date '+%F %T')] selesai: $(du -h "$DIR/harian/$NAMA.tar.gz.gpg" | cut -f1)"
