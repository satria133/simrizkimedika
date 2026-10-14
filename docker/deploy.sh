#!/usr/bin/env bash
# Deploy mLITE Rizki Medika ke VPS Ubuntu 22.04/24.04 (jalankan sebagai root atau via sudo).
#   git clone <repo> /opt/mlite && cd /opt/mlite/docker
#   cp .env.production.example .env.production && nano .env.production
#   sudo bash deploy.sh
# Aman dijalankan ulang (idempotent): instalasi/hardening dilewati bila sudah ada,
# container di-build ulang, password admin hanya diganti saat deploy pertama.
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=.env.production
COMPOSE=(docker compose -p mlite -f docker-compose.yaml -f docker-compose.prod.yaml --env-file "$ENV_FILE")

[ -f "$ENV_FILE" ] || { echo "!! $ENV_FILE belum ada. Salin dari .env.production.example lalu isi."; exit 1; }
if grep -q '<' "$ENV_FILE"; then echo "!! Masih ada nilai <...> di $ENV_FILE yang belum diisi."; exit 1; fi
chmod 600 "$ENV_FILE"
set -a; . "./$ENV_FILE"; set +a

echo "== 1. Paket dasar & Docker"
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  curl -fsSL https://get.docker.com | sh
fi
apt-get install -y ufw fail2ban unattended-upgrades rclone gnupg >/dev/null

echo "== 2. Firewall: hanya SSH, HTTP, HTTPS"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
# catatan: port yang di-publish Docker melewati ufw; karena itu MySQL TIDAK pernah di-publish (lihat compose)

echo "== 3. Hardening SSH & update otomatis"
if [ -s /root/.ssh/authorized_keys ] || ls /home/*/.ssh/authorized_keys >/dev/null 2>&1; then
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  systemctl reload ssh || systemctl reload sshd || true
else
  echo "   (lewati: belum ada SSH key; login password tetap aktif, pasang key lalu jalankan ulang)"
fi
systemctl enable --now fail2ban >/dev/null
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null || true

echo "== 4. Build & jalankan container"
PERTAMA=0
docker volume inspect mlite_mysql_data >/dev/null 2>&1 || PERTAMA=1
"${COMPOSE[@]}" up -d --build

echo "== 5. Tunggu database siap"
for i in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T mysql mysqladmin ping -uroot -p"$DB_ROOT_PASSWORD" --silent 2>/dev/null; then break; fi
  sleep 5
done

if [ "$PERTAMA" = 1 ]; then
  echo "== 6. Deploy pertama: ganti password admin bawaan"
  # tunggu init.sql (mlite_db.sql) + zz-rizkimedika.sql selesai diimpor
  for i in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" -N -e "SELECT value FROM ${DB_DATABASE}.mlite_settings WHERE field='theme_admin'" 2>/dev/null | grep -q rizkimedika; then break; fi
    sleep 5
  done
  PASS_ADMIN=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)
  HASH=$("${COMPOSE[@]}" exec -T php php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$PASS_ADMIN")
  "${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" "$DB_DATABASE" \
    -e "UPDATE mlite_users SET password='${HASH}' WHERE username='admin';"
  umask 077
  echo "admin / ${PASS_ADMIN}" > /root/mlite-admin-awal.txt
  echo "   Password admin baru disimpan di /root/mlite-admin-awal.txt (hapus setelah dicatat & diganti)."
fi

echo "== 7. Jadwal backup harian 02:00"
CRON="0 2 * * * root bash $(pwd)/backup.sh >> /var/log/mlite-backup.log 2>&1"
echo "$CRON" > /etc/cron.d/mlite-backup
chmod 644 /etc/cron.d/mlite-backup
[ -f /root/.config/rclone/rclone.conf ] || echo "   !! rclone belum dikonfigurasi: jalankan 'rclone config' untuk remote ${BACKUP_REMOTE%%:*}"

echo
echo "Selesai. Buka https://${DOMAIN}/admin"
"${COMPOSE[@]}" ps
