#!/bin/sh
# Railway entrypoint for Odoo 19.
#
# Runs as root only long enough to fix volume ownership and render the config,
# then hands the process to the image's own unprivileged `odoo` user.
set -eu

: "${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD is required (master password for the database manager)}"

# Railway mounts volumes root-owned, and the upstream image never chowns them.
mkdir -p /var/lib/odoo /mnt/extra-addons

# admin_passwd is the only secret in odoo.conf, so it is appended here rather
# than committed. It stays in the [options] section because the committed file
# has no other sections. Odoo rewrites this file if the master password is
# changed through the UI; that change is not persisted, and $ODOO_ADMIN_PASSWD
# remains the source of truth on the next boot.
cp /etc/odoo/odoo.conf.base /etc/odoo/odoo.conf
printf 'admin_passwd = %s\n' "$ODOO_ADMIN_PASSWD" >> /etc/odoo/odoo.conf

chown -R odoo:odoo /var/lib/odoo /mnt/extra-addons /etc/odoo/odoo.conf
chmod 640 /etc/odoo/odoo.conf

echo "boot: uid=$(id -u) dropping to odoo (uid $(id -u odoo)); config rendered at /etc/odoo/odoo.conf"

# Odoo 19 aborts at startup if the database role is literally named 'postgres'
# (odoo/cli/server.py: "Using the database user 'postgres' is a security risk").
# Railway's managed PostgreSQL hands out exactly that user, so fail loudly here
# instead of leaving a container that exits 1 on every boot.
if [ "${PGUSER:-}" = "postgres" ]; then
    echo "FATAL: PGUSER is 'postgres'. Odoo refuses to run as that role." >&2
    echo "       Create a scoped role instead, e.g.:" >&2
    echo "       CREATE ROLE odoo WITH LOGIN CREATEDB NOSUPERUSER NOCREATEROLE NOREPLICATION PASSWORD '...';" >&2
    exit 1
fi

# Hand off to the upstream entrypoint, which waits for PostgreSQL and then
# execs `odoo`. It reads ODOO_RC=/etc/odoo/odoo.conf from the base image.
exec setpriv --reuid=odoo --regid=odoo --init-groups /entrypoint.sh odoo
