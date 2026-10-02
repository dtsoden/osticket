# osTicket Docker image

A small image for [osTicket](https://osticket.com) built from the official release zip on top of the official `php:8.3-apache` image. On first start it installs osTicket from environment variables, so nobody has to click through `/setup`. Later starts skip the install, keep the existing config, and remove the `setup/` folder.

Images are published to `ghcr.io/dtsoden/osticket`, tagged with the osTicket version (for example `1.18.4`) and `latest`. Pin the version tag in production.

To try it locally, run this and then sign in at http://localhost:8080/scp with the `ADMIN_USER` and `ADMIN_PASS` from `docker-compose.yml`:

```bash
docker compose up -d
```

The first start waits for MariaDB, runs the installer and prints `osTicket installed` to the container log. Change every password in `docker-compose.yml` before using it for anything real.

Configuration is all environment variables. The install variables are only read on the first start, when `/data/ost-config.php` doesn't exist yet. After that, change those settings in the staff panel.

| Variable | Default | Purpose |
| --- | --- | --- |
| `DB_HOST` | required | Database host, optionally `host:port` |
| `DB_NAME` | `osticket` | Database name (created if missing and the user is allowed to) |
| `DB_USER`, `DB_PASS` | required | Database login |
| `DB_PREFIX` | `ost_` | Table prefix, must end in `_` |
| `DB_WAIT_TIMEOUT` | `120` | Seconds to wait for the database before giving up |
| `INSTALL_NAME` | `osTicket Helpdesk` | Helpdesk name |
| `INSTALL_EMAIL` | required | Helpdesk email address |
| `INSTALL_URL` | `http://localhost` | Public URL, used in links in emails |
| `INSTALL_SECRET` | random | Secret salt written to the config |
| `INSTALL_LANGUAGE` | `en_US` | Language for the default data |
| `ADMIN_FIRSTNAME`, `ADMIN_LASTNAME` | required | First admin's name |
| `ADMIN_EMAIL` | required | Admin email, must differ from `INSTALL_EMAIL` |
| `ADMIN_USER` | required | Admin username; `admin`, `admins`, `username` and `osticket` are rejected |
| `ADMIN_PASS` | required | Admin password, 6 to 128 characters |
| `TIMEZONE` | `UTC` | PHP and helpdesk timezone, for example `Europe/London` |
| `CRON_INTERVAL` | `5` | Minutes between `api/cron.php` runs (email fetching, scheduled tasks); `0` turns it off |
| `TRUSTED_PROXIES` | empty | Proxy IPs or CIDRs whose `X-Forwarded-For` is trusted; rewritten in the config on every start |
| `SMTP_HOST` | empty | SMTP server for outgoing mail |
| `SMTP_PORT` | by security | 587 for `starttls`, 465 for `tls`, 25 for `none` |
| `SMTP_SECURITY` | `starttls` | `starttls`, `tls` or `none` |
| `SMTP_USER`, `SMTP_PASS` | empty | SMTP login; leave empty for an unauthenticated relay |
| `SMTP_FROM` | empty | Envelope sender when osTicket doesn't set one |

Outgoing mail goes through msmtp, which the image sets up as PHP's sendmail. osTicket falls back to PHP `mail()` for any email address that has no SMTP account configured in Admin Panel > Emails, so the `SMTP_*` variables cover the simple case. An SMTP account set up inside osTicket takes priority over them. Incoming mail needs a mailbox configured in the staff panel and a non-zero `CRON_INTERVAL`.

Everything that has to survive a container rebuild lives in the `/data` volume: `ost-config.php`, the `plugins` folder (osTicket's `include/plugins` points there) and an `attachments` folder you can use with the "Attachments on the Filesystem" plugin. Attachments are stored in the database by default, so back up the database as well as the volume.

To upgrade osTicket, change `OSTICKET_VERSION` at the top of the `Dockerfile` and push to `main`. The workflow builds and publishes the new tag. Point your deployment at the new tag, then sign in to `/scp`, where osTicket offers to run its database upgrade. Read the osTicket release notes first, because some releases change the PHP versions they support.

The PHP extensions are gd, intl, mysqli, zip, apcu and opcache, on top of mbstring, xml, fileinfo, iconv and ctype from the base image. The imap extension is left out. Debian 13, which the PHP images are now built on, no longer ships the `libc-client` library it needs, and osTicket 1.18 fetches mail with its bundled laminas-mail library, so nothing depends on it.

The GitHub Actions workflow in `.github/workflows/publish.yml` builds for `linux/amd64` and `linux/arm64` on every push to `main` that touches the image, on demand, and once a week so the image picks up security fixes in the PHP base image. Pull requests build without publishing. The first time the workflow publishes, GitHub creates the package as private. To let servers pull it without logging in, open the package on GitHub, go to Package settings and change its visibility to public.
