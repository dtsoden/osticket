#!/bin/bash
set -euo pipefail

WEB_ROOT=/var/www/html
DATA_DIR=/data
CONFIG="$DATA_DIR/ost-config.php"

log() { echo "[osticket] $*"; }
die() { echo "[osticket] ERROR: $*" >&2; exit 1; }

# --- PHP runtime settings ---------------------------------------------------

TIMEZONE="${TIMEZONE:-UTC}"
[ -e "/usr/share/zoneinfo/$TIMEZONE" ] || die "unknown TIMEZONE '$TIMEZONE'"

{
    echo "date.timezone = $TIMEZONE"
    echo 'sendmail_path = "/usr/bin/msmtp -C /etc/msmtprc -t -i"'
} > /usr/local/etc/php/conf.d/zz-runtime.ini

# --- Outgoing mail ------------------------------------------------------------
# osTicket uses PHP mail() for any email address without its own SMTP account.
# msmtp turns that into an SMTP connection built from the SMTP_* variables.

if [ -n "${SMTP_HOST:-}" ]; then
    SMTP_SECURITY="${SMTP_SECURITY:-starttls}"
    case "$SMTP_SECURITY" in
        starttls) tls=on;  starttls=on;  default_port=587 ;;
        tls)      tls=on;  starttls=off; default_port=465 ;;
        none)     tls=off; starttls=off; default_port=25 ;;
        *) die "SMTP_SECURITY must be starttls, tls or none" ;;
    esac
    {
        echo "defaults"
        echo "tls $tls"
        echo "tls_starttls $starttls"
        echo "tls_trust_file /etc/ssl/certs/ca-certificates.crt"
        echo "syslog off"
        echo "logfile -"
        echo
        echo "account default"
        echo "host $SMTP_HOST"
        echo "port ${SMTP_PORT:-$default_port}"
        [ -n "${SMTP_FROM:-}" ] && echo "from $SMTP_FROM"
        if [ -n "${SMTP_USER:-}" ]; then
            echo "auth on"
            echo "user $SMTP_USER"
            echo "password ${SMTP_PASS:-}"
        else
            echo "auth off"
        fi
    } > /etc/msmtprc
    log "outgoing mail relays through $SMTP_HOST ($SMTP_SECURITY)"
else
    echo "# SMTP_HOST not set; outgoing mail without an osTicket SMTP account is disabled" > /etc/msmtprc
fi
chown www-data:www-data /etc/msmtprc
chmod 600 /etc/msmtprc

# --- Persistent data ----------------------------------------------------------

mkdir -p "$DATA_DIR/attachments" "$DATA_DIR/plugins"
# Refresh files that ship with osTicket (plugin update key) without touching
# plugins the admin added.
cp -a /usr/local/share/osticket-plugins/. "$DATA_DIR/plugins/"
chown -R www-data:www-data "$DATA_DIR"

rm -rf "$WEB_ROOT/include/plugins"
ln -s "$DATA_DIR/plugins" "$WEB_ROOT/include/plugins"
ln -sfn "$CONFIG" "$WEB_ROOT/include/ost-config.php"

is_installed() {
    [ -f "$CONFIG" ] && grep -q "define('OSTINSTALLED',TRUE);" "$CONFIG"
}

# --- First boot install -------------------------------------------------------

wait_for_db() {
    local timeout="${DB_WAIT_TIMEOUT:-120}"
    log "waiting up to ${timeout}s for the database at $DB_HOST"
    php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        [$host, $port] = array_pad(explode(":", getenv("DB_HOST"), 2), 2, 3306);
        $deadline = time() + (int) $argv[1];
        do {
            $db = @mysqli_connect($host, getenv("DB_USER"), getenv("DB_PASS"), "", (int) $port);
            if ($db) exit(0);
            sleep(2);
        } while (time() < $deadline);
        fwrite(STDERR, mysqli_connect_error() . "\n");
        exit(1);
    ' "$timeout" || die "database not reachable"
}

if is_installed; then
    log "existing install found, keeping $CONFIG"
else
    for var in DB_HOST DB_USER DB_PASS INSTALL_EMAIL ADMIN_FIRSTNAME ADMIN_LASTNAME ADMIN_EMAIL ADMIN_USER ADMIN_PASS; do
        [ -n "${!var:-}" ] || die "$var is required for the first install"
    done
    wait_for_db

    log "installing osTicket $OSTICKET_VERSION"
    cp "$WEB_ROOT/include/ost-sampleconfig.php" "$CONFIG"
    chown www-data:www-data "$CONFIG"
    chmod 640 "$CONFIG"

    if ! runuser -u www-data -- php /usr/local/bin/osticket-install.php; then
        # Leave no half-written config behind so the next start retries.
        rm -f "$CONFIG"
        die "install failed (see errors above)"
    fi
    chmod 440 "$CONFIG"
fi

# Settings that may change after install are rewritten in the config each boot.
if [ -n "${TRUSTED_PROXIES:-}" ]; then
    chmod 640 "$CONFIG"
    sed -i "s|^define('TRUSTED_PROXIES', *'[^']*');|define('TRUSTED_PROXIES', '${TRUSTED_PROXIES}');|" "$CONFIG"
    chmod 440 "$CONFIG"
fi

# osTicket warns in the staff panel while the installer is reachable.
rm -rf "$WEB_ROOT/setup"

# --- Cron ---------------------------------------------------------------------
# api/cron.php fetches email and runs scheduled tasks.

CRON_INTERVAL="${CRON_INTERVAL:-5}"
if [ "$CRON_INTERVAL" -gt 0 ] 2>/dev/null; then
    log "running cron every $CRON_INTERVAL minute(s)"
    (
        while sleep "$((CRON_INTERVAL * 60))"; do
            runuser -u www-data -- php "$WEB_ROOT/api/cron.php" || log "cron run failed"
        done
    ) &
else
    log "cron disabled (CRON_INTERVAL=$CRON_INTERVAL)"
fi

exec "$@"
