# syntax=docker/dockerfile:1

# ---------- Stage 1: frontend assets (vite) ----------
FROM node:22-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build && rm -rf node_modules

# ---------- Stage 2: PHP-FPM + Nginx + Supervisor ----------
FROM php:8.3-fpm

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        gettext-base \
        git \
        unzip \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev \
        libzip-dev \
        libicu-dev \
        libonig-dev \
        libxml2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        mysqli \
        pdo_mysql \
        intl \
        zip \
        bcmath \
        exif \
        ftp \
        opcache \
    && rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Aplikasi hasil stage 1 (sudah termasuk node build output)
COPY --from=assets /app /var/www/html

# Tiga project composer terpisah: core, citationStyleLanguage, paypal
RUN for d in \
        lib/pkp \
        plugins/generic/citationStyleLanguage \
        plugins/paymethod/paypal \
    ; do \
        composer install --no-dev --no-interaction --no-progress --optimize-autoloader \
            -d "/var/www/html/$d" || exit 1; \
    done

# PHP config
COPY docker/php/uploads.ini /usr/local/etc/php/conf.d/uploads.ini
COPY docker/php/security.ini /usr/local/etc/php/conf.d/security.ini
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# FPM harus dengar di loopback, container hanya expose nginx
RUN sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /usr/local/etc/php-fpm.d/www.conf

# Nginx template (domain di-substitusi saat container start)
RUN rm -f /etc/nginx/conf.d/default.conf /etc/nginx/sites-enabled/default \
    && mkdir -p /etc/nginx/templates
COPY docker/nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Supervisor
COPY docker/supervisord.conf /etc/supervisor/conf.d/ojs.conf

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/html/files /var/www/html/cache /var/www/html/registry \
    && chown -R www-data:www-data \
        /var/www/html/files \
        /var/www/html/cache \
        /var/www/html/registry \
        /var/www/html/public \
        /var/www/html/lib/pkp/lib/vendor \
    && chmod -R 775 \
        /var/www/html/files \
        /var/www/html/cache \
        /var/www/html/registry \
        /var/www/html/public

WORKDIR /var/www/html
EXPOSE 80

ENTRYPOINT ["entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/ojs.conf"]
