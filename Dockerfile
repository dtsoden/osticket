FROM php:8.3-apache

# osTicket release to build. Bump this (and nothing else) to upgrade.
ARG OSTICKET_VERSION=1.18.4

# PHP extensions osTicket uses. mbstring, xml, fileinfo, iconv and ctype are
# already compiled into the base image; opcache only needs enabling.
# imap is left out: Debian trixie no longer ships libc-client, and osTicket
# 1.18 fetches mail with its bundled laminas-mail library instead.
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd intl mysqli opcache zip; \
    pecl install apcu; \
    docker-php-ext-enable apcu; \
    rm -rf /tmp/pear; \
    # Drop the -dev packages but keep the shared libraries the extensions link to.
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    # Runtime tools: msmtp relays PHP mail() to an SMTP server, unzip unpacks the release.
    apt-get install -y --no-install-recommends ca-certificates msmtp unzip; \
    rm -rf /var/lib/apt/lists/*; \
    php -m | grep -qiE '^(apcu|gd|intl|mysqli|zip)$'

RUN set -eux; \
    curl -fsSL -o /tmp/osticket.zip \
        "https://github.com/osTicket/osTicket/releases/download/v${OSTICKET_VERSION}/osTicket-v${OSTICKET_VERSION}.zip"; \
    unzip -q /tmp/osticket.zip -d /tmp/osticket; \
    rm -rf /var/www/html; \
    mv /tmp/osticket/upload /var/www/html; \
    mv /tmp/osticket/scripts /usr/local/share/osticket-scripts; \
    rm -rf /tmp/osticket /tmp/osticket.zip; \
    # Keep a pristine copy of the bundled plugins; /data/plugins is seeded from it.
    cp -a /var/www/html/include/plugins /usr/local/share/osticket-plugins; \
    chown -R root:root /var/www/html; \
    echo "${OSTICKET_VERSION}" > /usr/local/share/osticket-version; \
    echo "ServerName localhost" > /etc/apache2/conf-enabled/servername.conf

COPY docker/php.ini /usr/local/etc/php/conf.d/osticket.ini
COPY docker/install.php /usr/local/bin/osticket-install.php
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/osticket-entrypoint

# Config file, attachments and plugins live here.
VOLUME /data

ENV OSTICKET_VERSION=${OSTICKET_VERSION}

EXPOSE 80

ENTRYPOINT ["osticket-entrypoint"]
CMD ["apache2-foreground"]
