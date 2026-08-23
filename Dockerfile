#this is a optional phase for your app
FROM node:24-alpine AS frontend

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY vite.config.js ./
COPY resources ./resources

RUN npm run build

#config for the laravel app production level cicd

FROM php:8.5-alpine AS production

#install system packages and php run time applications
RUN apk add --no-cache \
        nginx \
        supervisor \
        sqlite-libs \
        libpng libjpeg-turbo libwebp freetype \
        icu-libs \
        libpq \
    && apk add --no-cache --virtual .build-deps \
       $PHPIZE_DEPS \
    sqlite-dev  \
    postgresql-dev \
    libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev \
    icu-dev \
    linux-headers \
    curl-dev \
    libxml2-dev \
    oniguruma-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-libwebp \
    && docker-php-ext-install -j$(nproc) \
    pdo-sqlite pdo_mysql pdo_pgsql \
    gd intl opcache pcntl bcmath \
    && apk del .build-deps \
    && rm -rf /tmp/*

#-j$(nproc) docker image eke cpu eke cores tika fastly compile

#php production config
COPY docker/php.ini /usr/local/etc/php/conf.d/99-production.ini

#nginx config
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

#supervisor config
COPY docker/supervisord.conf /etc/supervisord.conf

WORKDIR /var/www/html

#install composer
COPY  --from=composer:2 /usr/bin/composer /usr/bin/composer

#install php  dependencies (production only)
COPY composer.json composer.lock* ./
RUN composer install --no-dev --no-script --no-interaction --prefer-dist --optimize-autoloader

#copy application code
COPY . .

#re-run composer scripts now that all code is present
RUN composer dump-autoload --optimize

#copy compiled frontend assets from stage 1
COPY --from=frontend /app/public/build/ ./public/build/

#prepare storage and cache directories
RUN mkdir -p \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache \
    database \
    && chown -R www-data:www-data storage bootstrap/cache database \
    && chmod -R 775 storage bootstrap/cache database

#entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q0- http://localhost/up || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord","-c","/etc/supervisord.conf"]







