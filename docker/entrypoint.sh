#!/bin/sh
set -eu

APP_ROOT=/var/www/html
CONFIG="$APP_ROOT/config.inc.php"

: "${APP_URL:=http://localhost:8080}"
: "${APP_DOMAIN:=localhost}"
: "${DB_DRIVER:=mysqli}"
: "${DB_HOST:=db}"
: "${DB_NAME:=ojs}"
: "${DB_USER:=ojs}"
: "${DB_PASSWORD:=ojs}"
: "${SALT:=${DB_PASSWORD}}"
: "${INSTALLED:=On}"
: "${TIME_ZONE:=Asia/Jakarta}"
: "${FORCE_SSL:=Off}"
: "${MAX_UPLOAD_SIZE:=20m}"

# Render nginx config: domain diambil dari env saat container start,
# bukan saat build, jadi satu image bisa dipakai untuk banyak domain.
export APP_DOMAIN MAX_UPLOAD_SIZE
envsubst '${APP_DOMAIN} ${MAX_UPLOAD_SIZE}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/conf.d/default.conf

# config.inc.php hanya dibuat sekali. Kalau operator sudah mengeditnya
# (misal lewat volume), file itu tidak ditimpa.
if [ ! -f "$CONFIG" ]; then
    echo "entrypoint: membuat config.inc.php dari template"

    # ponytail: sed pakai delimiter '|'. Password/salt yang mengandung
    # '|', '&' atau '\' akan merusak output — set lewat config.inc.php manual.
    sed \
        -e "s|^installed = .*|installed = ${INSTALLED}|" \
        -e "s|^base_url = .*|base_url = \"${APP_URL}\"|" \
        -e "s|^driver = .*|driver = ${DB_DRIVER}|" \
        -e "s|^host = .*|host = ${DB_HOST}|" \
        -e "s|^username = .*|username = ${DB_USER}|" \
        -e "s|^password = .*|password = ${DB_PASSWORD}|" \
        -e "s|^name = .*|name = ${DB_NAME}|" \
        -e "s|^salt = .*|salt = \"${SALT}\"|" \
        -e "s|^time_zone = .*|time_zone = \"${TIME_ZONE}\"|" \
        -e "s|^force_ssl = .*|force_ssl = ${FORCE_SSL}|" \
        -e "s|^restful_urls = .*|restful_urls = On|" \
        -e "s|^trust_x_forwarded_for = .*|trust_x_forwarded_for = On|" \
        "$APP_ROOT/config.TEMPLATE.inc.php" > "$CONFIG"
fi

chown www-data:www-data "$CONFIG"
chmod 640 "$CONFIG"

mkdir -p "$APP_ROOT/files" "$APP_ROOT/cache" "$APP_ROOT/registry"
chown -R www-data:www-data "$APP_ROOT/files" "$APP_ROOT/cache" "$APP_ROOT/registry"

echo "entrypoint: APP_DOMAIN=$APP_DOMAIN APP_URL=$APP_URL DB_HOST=$DB_HOST"
exec "$@"
