#!/usr/bin/env bash
# Deploy mLITE Rizki Medika ke VPS Ubuntu 22.04/24.04.
#   git clone https://github.com/satria133/simrizkimedika.git /opt/rizkimedika && cd /opt/rizkimedika/docker
#   cp .env.production.example .env.production && nano .env.production
#   sudo bash deploy.sh
#
# Dua mode (atur SHARED_HOST di .env.production):
#   SHARED_HOST=no  : VPS khusus. Caddy memegang 80/443; firewall, hardening SSH, fail2ban dipasang.
#   SHARED_HOST=yes : VPS bersama yang sudah punya nginx host + certbot dan aplikasi lain.
#                     Container hanya di 127.0.0.1:APP_LOCAL_PORT; site nginx + sertifikat certbot ditambahkan;
#                     firewall/SSH/aplikasi lain TIDAK disentuh.
# Aman dijalankan ulang: password admin hanya diganti saat deploy pertama.
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=.env.production
[ -f "$ENV_FILE" ] || { echo "!! $ENV_FILE belum ada. Salin dari .env.production.example lalu isi."; exit 1; }
if grep -q '<' "$ENV_FILE"; then echo "!! Masih ada nilai <...> di $ENV_FILE yang belum diisi."; exit 1; fi
chmod 600 "$ENV_FILE"
set -a; . "./$ENV_FILE"; set +a
SHARED_HOST=${SHARED_HOST:-no}
APP_LOCAL_PORT=${APP_LOCAL_PORT:-8200}
if [ "$SHARED_HOST" = yes ]; then OVERRIDE=docker-compose.shared.yaml; else OVERRIDE=docker-compose.prod.yaml; fi
COMPOSE=(docker compose -p mlite -f docker-compose.yaml -f "$OVERRIDE" --env-file "$ENV_FILE")
echo "Mode: SHARED_HOST=$SHARED_HOST ($OVERRIDE)"

echo "== 1. Docker"
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  curl -fsSL https://get.docker.com | sh
fi
command -v gpg >/dev/null || apt-get install -y gnupg >/dev/null
command -v rclone >/dev/null || apt-get install -y rclone >/dev/null

if [ "$SHARED_HOST" != yes ]; then
  apt-get install -y ufw fail2ban unattended-upgrades >/dev/null
  echo "== 2. Firewall: hanya SSH, HTTP, HTTPS"
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  # catatan: port yang di-publish Docker melewati ufw; karena itu MySQL TIDAK pernah di-publish

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
else
  echo "== 2-3. VPS bersama: firewall, SSH, dan aplikasi lain tidak diubah"
fi

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
  for i in $(seq 1 90); do
    if "${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" -N -e "SELECT value FROM ${DB_DATABASE}.mlite_settings WHERE field='theme_admin'" 2>/dev/null | grep -q rizkimedika; then break; fi
    sleep 5
  done
  PASS_ADMIN=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)
  HASH=$("${COMPOSE[@]}" exec -T php php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$PASS_ADMIN")
  "${COMPOSE[@]}" exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD" "$DB_DATABASE" \
    -e "UPDATE mlite_users SET password='${HASH}' WHERE username='admin';"
  umask 077
  echo "admin / ${PASS_ADMIN}" > /root/mlite-admin-awal.txt
  umask 022
  echo "   Password admin baru disimpan di /root/mlite-admin-awal.txt (hapus setelah dicatat & diganti)."
fi

if [ "$SHARED_HOST" = yes ]; then
  echo "== 7. Site nginx host + sertifikat HTTPS (certbot)"
  SITE=/etc/nginx/sites-available/$DOMAIN
  if [ ! -f "$SITE" ]; then
    sed -e "s/\${DOMAIN}/$DOMAIN/g" -e "s/\${APP_LOCAL_PORT}/$APP_LOCAL_PORT/g" host-nginx.conf.template > "$SITE"
    ln -sf "$SITE" /etc/nginx/sites-enabled/
    nginx -t
    systemctl reload nginx
    if [ -n "${ACME_EMAIL:-}" ]; then EMAIL_ARG=(-m "$ACME_EMAIL"); else EMAIL_ARG=(); fi   # kosong = pakai akun certbot yang sudah ada
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos "${EMAIL_ARG[@]}" --redirect
  else
    echo "   site $DOMAIN sudah ada, dilewati"
  fi
fi

echo "== 8. Jadwal backup harian 02:00"
echo "0 2 * * * root bash $(pwd)/backup.sh >> /var/log/mlite-backup.log 2>&1" > /etc/cron.d/mlite-backup
chmod 644 /etc/cron.d/mlite-backup
if [ -z "${BACKUP_REMOTE:-}" ]; then
  echo "   !! BACKUP_REMOTE kosong: backup hanya disimpan lokal di /var/backups/mlite"
elif [ ! -f /root/.config/rclone/rclone.conf ]; then
  echo "   !! rclone belum dikonfigurasi: jalankan 'sudo rclone config' untuk remote ${BACKUP_REMOTE%%:*}"
fi

echo
echo "Selesai. Buka https://${DOMAIN}/admin"
"${COMPOSE[@]}" ps
