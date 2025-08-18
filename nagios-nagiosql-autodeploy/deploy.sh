#!/usr/bin/env bash
# Nagios Core + Plugins + (optional) NagiosQL one-shot installer
# Target: Ubuntu 22.04 LTS
# Usage:
#   sudo -i
#   bash deploy.sh
#
# Or with custom env:
#   DOMAIN="nagios.example.com" EMAIL="you@example.com" \
#   ADMIN_USER="nagiosadmin" ADMIN_PASS="Str0ngP@ss!" \
#   PHP_TZ="Asia/Dhaka" NQ_ENABLE=1 \
#   bash deploy.sh
set -Eeuo pipefail

# ---------- Config (env-overridable) ----------
NAGIOS_VER="${NAGIOS_VER:-4.5.5}"
PLUGINS_VER="${PLUGINS_VER:-2.4.6}"

DOMAIN="${DOMAIN:-nagios.grameencybernet.net}"
EMAIL="${EMAIL:-root@localhost}"
ADMIN_USER="${ADMIN_USER:-nagiosadmin}"
# random default if not provided
ADMIN_PASS="${ADMIN_PASS:-$(tr -dc 'A-Za-z0-9@%+=._-' </dev/urandom | head -c 20)}"
PHP_TZ="${PHP_TZ:-Asia/Dhaka}"
NQ_ENABLE="${NQ_ENABLE:-1}"   # 1=install NagiosQL, 0=skip

CORE_URL="https://github.com/NagiosEnterprises/nagioscore/releases/download/nagios-${NAGIOS_VER}/nagios-${NAGIOS_VER}.tar.gz"
PLUGINS_URL="https://github.com/nagios-plugins/nagios-plugins/releases/download/release-${PLUGINS_VER}/nagios-plugins-${PLUGINS_VER}.tar.gz"
# We'll try multiple mirrors for NagiosQL to be resilient
NQ_VER="3.5.0"
NQ_URLS=(
  "https://downloads.sourceforge.net/project/nagiosql/nagiosql/NagiosQL%20${NQ_VER}/nagiosql-${NQ_VER}.tar.gz"
  "https://netcologne.dl.sourceforge.net/project/nagiosql/nagiosql/NagiosQL%20${NQ_VER}/nagiosql-${NQ_VER}.tar.gz"
  "https://pilotfiber.dl.sourceforge.net/project/nagiosql/nagiosql/NagiosQL%20${NQ_VER}/nagiosql-${NQ_VER}.tar.gz"
)

INFO="/root/nagios_install_info.txt"
SRC="/usr/local/src"
HTPASS="/usr/local/nagios/etc/htpasswd.users"
NAGIOS_ETC="/usr/local/nagios/etc"
NAGIOS_VAR="/usr/local/nagios/var"
NAGIOS_RW="${NAGIOS_VAR}/rw"
CMD_PIPE="${NAGIOS_RW}/nagios.cmd"
STATUS_DAT="${NAGIOS_VAR}/status.dat"
LOCK_FILE="${NAGIOS_VAR}/nagios.lock"
NQ_BASE="/etc/nagiosql"
NQ_HOSTS="${NQ_BASE}/hosts"
NQ_SERVS="${NQ_BASE}/services"

# ---------- Preconditions ----------
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo -i)"; exit 1
fi

echo "[+] Updating apt & installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  apache2 apache2-utils libapache2-mod-php \
  php php-cli php-mysql php-xml php-gd php-curl php-zip \
  mariadb-server mariadb-client \
  build-essential autoconf automake libtool pkg-config \
  gcc make g++ gettext libgd-dev libssl-dev \
  libmariadb-dev libmariadb-dev-compat libdbi-dev libpq-dev libperl-dev \
  snmp libsnmp-dev \
  python3-certbot-apache \
  wget curl tar unzip ca-certificates jq || true

echo "[+] Ensuring users/groups"
id -u nagios >/dev/null 2>&1 || useradd -m -s /bin/bash nagios
getent group nagcmd >/dev/null 2>&1 || groupadd -r nagcmd
usermod -a -G nagcmd nagios
usermod -a -G nagios,nagcmd www-data

mkdir -p "${SRC}"

# ---------- Build: Nagios Core ----------
echo "[+] Installing Nagios Core ${NAGIOS_VER}"
cd "${SRC}"
if [[ ! -f "nagios-${NAGIOS_VER}.tar.gz" ]]; then
  wget -q -O "nagios-${NAGIOS_VER}.tar.gz" "${CORE_URL}"
fi
rm -rf "nagios-${NAGIOS_VER}"
tar xzf "nagios-${NAGIOS_VER}.tar.gz"
cd "nagios-${NAGIOS_VER}"
./configure --with-nagios-user=nagios --with-nagios-group=nagios --with-command-group=nagcmd >/dev/null
make all >/dev/null
make install >/dev/null
make install-init >/dev/null || make install-daemoninit >/dev/null || true
make install-commandmode >/dev/null
make install-config >/dev/null
make install-webconf >/dev/null || true  # we'll replace with our vhost

# ---------- Build: Nagios Plugins ----------
echo "[+] Installing Nagios Plugins ${PLUGINS_VER}"
cd "${SRC}"
if [[ ! -f "nagios-plugins-${PLUGINS_VER}.tar.gz" ]]; then
  wget -q -O "nagios-plugins-${PLUGINS_VER}.tar.gz" "${PLUGINS_URL}"
fi
rm -rf "nagios-plugins-${PLUGINS_VER}"
tar xzf "nagios-plugins-${PLUGINS_VER}.tar.gz"
cd "nagios-plugins-${PLUGINS_VER}"
./configure --with-nagios-user=nagios --with-nagios-group=nagios >/dev/null
make >/dev/null
make install >/dev/null

# ---------- HTTP Basic auth ----------
echo "[+] Configuring web auth for ${ADMIN_USER}"
install -d -m 755 -o root -g root "$(dirname "${HTPASS}")"
htpasswd -b -c "${HTPASS}" "${ADMIN_USER}" "${ADMIN_PASS}" >/dev/null

# ---------- Apache vhost (with redirect / -> /nagios) ----------
echo "[+] Writing Apache vhost"
cat >/etc/apache2/sites-available/nagios-suite.conf <<EOF
<VirtualHost *:80>
  ServerName ${DOMAIN}
  # Redirect only root path to /nagios/
  RedirectMatch "^/$" "/nagios/"

  ScriptAlias /nagios/cgi-bin "/usr/local/nagios/sbin"
  Alias /nagios "/usr/local/nagios/share"
  Alias /nagiosql "/var/www/nagiosql"

  <Directory "/usr/local/nagios/sbin">
      Options ExecCGI
      AllowOverride None
      AuthType Basic
      AuthName "Nagios Access"
      AuthUserFile ${HTPASS}
      Require valid-user
  </Directory>

  <Directory "/usr/local/nagios/share">
      Options None
      AllowOverride None
      AuthType Basic
      AuthName "Nagios Access"
      AuthUserFile ${HTPASS}
      Require valid-user
  </Directory>

  <Directory "/var/www/nagiosql">
      Options FollowSymLinks
      AllowOverride All
      Require all granted
  </Directory>

  ErrorLog \${APACHE_LOG_DIR}/nagios_error.log
  CustomLog \${APACHE_LOG_DIR}/nagios_access.log combined
</VirtualHost>
EOF

# Turn off the stock site if present, enable ours
a2dissite 000-default.conf >/dev/null 2>&1 || true
a2dissite nagios.conf       >/dev/null 2>&1 || true
a2enmod cgi rewrite headers >/dev/null 2>&1 || true
a2ensite nagios-suite.conf  >/dev/null

# ---------- PHP timezone ----------
echo "[+] Setting PHP timezone: ${PHP_TZ}"
for INI in /etc/php/*/apache2/php.ini; do
  [[ -f "$INI" ]] || continue
  sed -ri 's~^;?\s*date\.timezone\s*=.*$~date.timezone = '"${PHP_TZ}"'~' "$INI"
done

# ---------- Nagios config set to /etc/nagiosql ----------
echo "[+] Preparing /etc/nagiosql config tree & minimal objects"
mkdir -p "${NQ_HOSTS}" "${NQ_SERVS}" "${NQ_BASE}"/{backup}
# Base sets
cat >"${NQ_BASE}/timeperiods.cfg" <<'CFG'
define timeperiod { timeperiod_name 24x7        alias 24 Hours A Day, 7 Days A Week
sunday 00:00-24:00 ; monday 00:00-24:00 ; tuesday 00:00-24:00 ; wednesday 00:00-24:00
thursday 00:00-24:00 ; friday 00:00-24:00 ; saturday 00:00-24:00 }
CFG

cat >"${NQ_BASE}/commands.cfg" <<'CFG'
define command { command_name check_ping command_line /usr/local/nagios/libexec/check_ping -H $HOSTADDRESS$ -w $ARG1$ -c $ARG2$ -p 5 -t 20 }
define command { command_name check_ssh  command_line /usr/local/nagios/libexec/check_ssh -H $HOSTADDRESS$ }
define command { command_name notify-host-by-email command_line /usr/bin/printf "%b" "Subject: ** HOST $HOSTSTATE$ ** $HOSTALIAS$ is $HOSTSTATE$! on $LONGDATETIME$\n\n$HOSTOUTPUT$\n" | /usr/sbin/sendmail -t $CONTACTEMAIL$ }
define command { command_name notify-service-by-email command_line /usr/bin/printf "%b" "Subject: ** SERVICE $SERVICESTATE$ ** $HOSTALIAS$/$SERVICEDESC$ on $LONGDATETIME$\n\n$SERVICEOUTPUT$\n" | /usr/sbin/sendmail -t $CONTACTEMAIL$ }
CFG

cat >"${NQ_BASE}/contacts.cfg" <<CFG
define contact{
  contact_name            ${ADMIN_USER}
  alias                   Nagios Admin
  service_notification_period 24x7
  host_notification_period    24x7
  service_notification_options w,u,c,r
  host_notification_options    d,u,r
  service_notification_commands notify-service-by-email
  host_notification_commands    notify-host-by-email
  email                   ${EMAIL}
}
define contactgroup{
  contactgroup_name admins
  alias             Nagios Administrators
  members           ${ADMIN_USER}
}
CFG

cat >"${NQ_BASE}/hostgroups.cfg" <<'CFG'
define hostgroup{
  hostgroup_name demo-servers
  alias          Demo Servers
}
CFG

# Demo hosts
cat >"${NQ_HOSTS}/demo-router.cfg" <<'CFG'
define host {
  host_name demo-router
  alias Demo Router
  display_name Demo Router
  address 192.168.1.1
  max_check_attempts 3
  check_interval 5
  retry_interval 1
  notification_interval 30
  check_period 24x7
  notification_period 24x7
  contact_groups admins
  active_checks_enabled 1
  passive_checks_enabled 1
  register 1
}
CFG

cat >"${NQ_HOSTS}/demo-server.cfg" <<'CFG'
define host {
  host_name demo-server
  alias Demo Linux Server
  display_name Demo Linux Server
  address 192.168.1.100
  max_check_attempts 3
  check_interval 5
  retry_interval 1
  notification_interval 30
  check_period 24x7
  notification_period 24x7
  contact_groups admins
  active_checks_enabled 1
  passive_checks_enabled 1
  register 1
}
CFG

# Demo services
cat >"${NQ_SERVS}/demo-services.cfg" <<'CFG'
define service {
  host_name demo-router
  service_description PING
  display_name PING Service
  check_command check_ping!100.0,20%!500.0,60%
  max_check_attempts 3
  check_interval 5
  retry_interval 1
  notification_interval 30
  check_period 24x7
  notification_period 24x7
  contact_groups admins
  active_checks_enabled 1
  register 1
}
define service {
  host_name demo-server
  service_description PING
  display_name PING Service
  check_command check_ping!100.0,20%!500.0,60%
  max_check_attempts 3
  check_interval 5
  retry_interval 1
  notification_interval 30
  check_period 24x7
  notification_period 24x7
  contact_groups admins
  active_checks_enabled 1
  register 1
}
define service {
  host_name demo-server
  service_description SSH
  display_name SSH Service
  check_command check_ssh
  max_check_attempts 3
  check_interval 5
  retry_interval 1
  notification_interval 30
  check_period 24x7
  notification_period 24x7
  contact_groups admins
  active_checks_enabled 1
  register 1
}
CFG

# Permissions for nagios to read and for web to write later if using NagiosQL
chown -R www-data:www-data "${NQ_BASE}"
chmod -R a+rX "${NQ_BASE}"

# Point nagios to /etc/nagiosql only, disable default object files
echo "[+] Pointing Nagios to /etc/nagiosql (and disabling stock objects)"
NAGCFG="${NAGIOS_ETC}/nagios.cfg"
cp -a "${NAGCFG}"{,.bak.$(date +%F-%H%M)}
# comment out all stock cfg_file from objects/
sed -ri '/^cfg_file=\/usr\/local\/nagios\/etc\/objects\// s/^/# DISABLED by autodeploy: /' "${NAGCFG}"
sed -ri '/^cfg_dir=\/usr\/local\/nagios\/etc\/servers/ s/^/# DISABLED by autodeploy: /' "${NAGCFG}"
# ensure our dir present (unique)
grep -q '^cfg_dir=/etc/nagiosql$' "${NAGCFG}" || echo 'cfg_dir=/etc/nagiosql' >> "${NAGCFG}"
# external command processing on
sed -ri 's/^check_external_commands=.*/check_external_commands=1/' "${NAGCFG}"
# set proper file paths
sed -ri 's|^command_file=.*|command_file='"${CMD_PIPE}"'|' "${NAGCFG}"
sed -ri 's|^status_file=.*|status_file='"${STATUS_DAT}"'|' "${NAGCFG}"

# ---------- CGI authz ----------
echo "[+] Setting CGI authorizations"
CGICFG="${NAGIOS_ETC}/cgi.cfg"
cp -a "${CGICFG}"{,.bak.$(date +%F-%H%M)} || true
sed -ri 's/^use_authentication=.*/use_authentication=1/' "${CGICFG}" || true
for k in system_information configuration_information system_commands all_services all_hosts all_service_commands all_host_commands; do
  sed -ri "s/^authorized_for_${k}=.*$/authorized_for_${k}=${ADMIN_USER}/" "${CGICFG}" || echo "authorized_for_${k}=${ADMIN_USER}" >> "${CGICFG}"
done
grep -q '^authorized_for_read_only' "${CGICFG}" || echo "authorized_for_read_only=" >> "${CGICFG}"

# ---------- External command pipe & perms ----------
echo "[+] Fixing external command pipe permissions"
install -d -m 2775 -o nagios -g nagcmd "${NAGIOS_RW}"
touch "${CMD_PIPE}"; chown nagios:nagcmd "${CMD_PIPE}"; chmod 660 "${CMD_PIPE}"
chown -R nagios:nagios "${NAGIOS_VAR}"
chmod 775 "${NAGIOS_VAR}"

# ---------- NagiosQL (optional) ----------
NQ_DB_PASS="$(tr -dc 'A-Za-z0-9@%+=._-' </dev/urandom | head -c 24)"
if [[ "${NQ_ENABLE}" == "1" ]]; then
  echo "[+] Deploying NagiosQL ${NQ_VER} (files + database user)"
  # DB create
  mariadb -u root -e "CREATE DATABASE IF NOT EXISTS nagiosql CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mariadb -u root -e "CREATE USER IF NOT EXISTS 'nagiosql'@'localhost' IDENTIFIED BY '${NQ_DB_PASS}';"
  mariadb -u root -e "ALTER USER 'nagiosql'@'localhost' IDENTIFIED BY '${NQ_DB_PASS}'; FLUSH PRIVILEGES;"
  # Files
  mkdir -p /var/www
  rm -rf /var/www/nagiosql
  cd "${SRC}"
  ok=0
  for u in "${NQ_URLS[@]}"; do
    echo "    trying $u"
    if wget -q -O "nagiosql-${NQ_VER}.tar.gz" "$u"; then ok=1; break; fi
  done
  if [[ "$ok" -eq 1 ]]; then
    tar xzf "nagiosql-${NQ_VER}.tar.gz"
    mv "nagiosql-${NQ_VER}" /var/www/nagiosql
    chown -R www-data:www-data /var/www/nagiosql
    chmod -R 755 /var/www/nagiosql
  else
    echo "[-] WARNING: Could not download NagiosQL archive; skip files (DB user created)."
  fi
fi

# ---------- Validate & restart ----------
echo "[+] apache2ctl configtest"
apache2ctl configtest
echo "[+] Pre-flight check"
/usr/local/nagios/bin/nagios -v "${NAGIOS_ETC}/nagios.cfg"

echo "[+] Restarting services"
systemctl enable --now apache2
systemctl enable --now nagios
systemctl restart apache2
systemctl restart nagios

# ---------- Optional Let's Encrypt ----------
if command -v certbot >/dev/null 2>&1; then
  if [[ -n "${DOMAIN}" && "${DOMAIN}" != "nagios.local" ]]; then
    echo "[+] Attempting Let's Encrypt (will only work if port 80 is reachable)"
    certbot --apache -d "${DOMAIN}" -m "${EMAIL}" --agree-tos -n --redirect || true
  fi
fi

# ---------- Info file ----------
echo "[+] Writing info to ${INFO}"
{
  echo "==== Nagios Suite Autodeploy ($(date -Iseconds)) ===="
  echo "Domain         : ${DOMAIN}"
  echo "URLs           : http://${DOMAIN}/  → redirects to  /nagios"
  echo "Nagios Core    : http(s)://${DOMAIN}/nagios"
  echo "NagiosQL       : http(s)://${DOMAIN}/nagiosql  (if enabled)"
  echo "Admin user     : ${ADMIN_USER}"
  echo "Admin pass     : ${ADMIN_PASS}"
  if [[ "${NQ_ENABLE}" == "1" ]]; then
    echo "NagiosQL DB    : db=nagiosql user=nagiosql pass=${NQ_DB_PASS} host=localhost"
  fi
  echo "Sites-enabled  : $(ls -1 /etc/apache2/sites-enabled/ | tr '\n' ' ')"
} | tee "${INFO}"

echo
echo "All done ✅"
echo "Open: http://${DOMAIN}/  (auth: ${ADMIN_USER} / ${ADMIN_PASS})"
