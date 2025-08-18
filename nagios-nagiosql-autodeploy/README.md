# Nagios Suite Autodeploy (Ubuntu 22.04)

One-shot installer for **Nagios Core + Plugins** with a clean Apache vhost that
redirects `/` → `/nagios/`. Optionally deploys **NagiosQL 3.5.0** (files + DB user).

## Quick start
```bash
sudo -i
unzip nagios-suite-autodeploy.zip
cd nagios-suite-autodeploy
bash deploy.sh
```

## Recommended (custom) run
```bash
DOMAIN="nagios.yourdomain.com" \
EMAIL="you@example.com" \
ADMIN_USER="nagiosadmin" \
ADMIN_PASS="StrongP@ss#2025" \
PHP_TZ="Asia/Dhaka" \
NQ_ENABLE=1 \
bash deploy.sh
```

## What you get
- Nagios Core **4.5.5** (built from source)
- Nagios Plugins **2.4.6**
- Apache vhost `nagios-suite.conf` (HTTP 80) with:
  - Basic Auth on `/nagios` & `/nagios/cgi-bin`
  - Root redirect **/** → **/nagios/**
  - Alias `/nagiosql` (if enabled)
- PHP timezone fixed (`date.timezone`)
- Nagios configured to load only `/etc/nagiosql` objects
  (stock `objects/*.cfg` are disabled to avoid duplicates)
- Demo objects in `/etc/nagiosql`:
  - Hosts: `demo-router (192.168.1.1)`, `demo-server (192.168.1.100)`
  - Services: PING (both), SSH (demo-server)
  - Contact **nagiosadmin**, contactgroup **admins**, timeperiod **24x7**
- External command pipe ready (`check_external_commands=1`)
- **Optional**: NagiosQL 3.5.0 files in `/var/www/nagiosql` and DB user `nagiosql`

After install:
- Browse **http://$DOMAIN/** → redirects to **/nagios/**
- Credentials: see `/root/nagios_install_info.txt`

## Let's Encrypt (optional)
If port **80** is reachable from the internet, the script will try:
```
certbot --apache -d $DOMAIN --agree-tos -m $EMAIL --redirect -n
```
Failure here is harmless; TLS can be configured later.

## Re-run safety
The script is idempotent where practical. Re-running will:
- Keep/overwrite vhost
- Keep existing `nagios` users/groups
- Overwrite demo configs in `/etc/nagiosql`
- Re-check Apache+Nagios pre-flight and restart services

---

**Tested on Ubuntu 22.04 LTS**. For other distros, adapt package names & paths.
