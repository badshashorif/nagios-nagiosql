# Nagios + NagiosQL One-Host (Docker)

Reproducible Docker setup for **Nagios Core** + **NagiosQL** with Caddy reverse-proxy, MariaDB,
persistent volumes, and PEAR mounted via a named volume so redeploys don't lose it.

---

## Quick Start

1. **Clone & prepare**
   ```bash
   git clone <your-repo-url>.git nagios-onehost
   cd nagios-onehost
   cp .env.example .env
   mkdir -p secrets ssmtp plugins
   ```

2. **Fill `.env`**
   - `TZ=Asia/Dhaka`
   - `NAGIOS_HOST=monitor.example.com` (your DNS for Caddy auto-HTTPS)
   - `NAGIOS_AUTH_USERS=nagiosadmin`

3. **Create secrets**
   ```bash
   printf '%s' 'SuperRoot!' > secrets/db-root-password
   printf '%s' 'SqlUserPass!' > secrets/nagiosql-db-password
   docker run --rm httpd:2.4-alpine htpasswd -nbB nagiosadmin 'ChangeMe123' > secrets/nagios-htpasswd
   ```

4. **(Optional) Configure mail** – copy and edit:
   ```bash
   cp ssmtp/ssmtp.conf.example ssmtp/ssmtp.conf
   cp ssmtp/revaliases.example ssmtp/revaliases
   ```

5. **Bootstrap PEAR into named volume**
   ```bash
   ./bin/bootstrap-pear.sh
   ```

6. **Bring up the stack**
   ```bash
   docker compose up -d
   ```

7. **Prepare DB grants (smoother NagiosQL installer)**
   ```bash
   ./bin/db-prepare.sh
   ```

8. **Run the NagiosQL web installer (first run only)**
   - Visit `https://<NAGIOS_HOST>/nagiosql/install/install.php` (or `http://host:80` if no TLS)
   - Use:
     - **Database Server**: `db`
     - **Port**: `3306`
     - **Database**: `nagiosql`
     - **NagiosQL DB User**: `nagiosql` with password from `secrets/nagiosql-db-password`
     - **Administrative DB User**: `root` with password from `secrets/db-root-password`
   - Finish; then **delete the install dir** when prompted.

9. **In NagiosQL → Administration → Config targets** set directories (these defaults match this compose):
   - Base: `/etc/nagios/`
   - Import dir: `/etc/nagios/objects/`
   - Nagios binary: `/opt/nagios/bin/nagios`
   - Nagios CGI file: `/etc/nagios/cgi.cfg`
   - Nagios config file: `/etc/nagios/nagios.cfg`
   - Resource file: `/etc/nagios/resource.cfg`
   - Version: **4.x**

10. **Write configs & restart Nagios (in NagiosQL)**
    - Tools → *Write configuration files* → **Do it**
    - Tools → *Check configuration files* → **Do it**
    - Tools → *Restart Nagios* → **Do it**

11. **Verify**
    ```bash
    ./bin/checks.sh
    ```

---

## Notes

- **PEAR persistence**: mounted at `/usr/share/pear` via the `nagiosql-pear` volume.
  Re-deploys keep it, so *Requirements → PEAR* stays OK.
- **Mail**: `ssmtp` files are bind-mounted read-only into the Nagios container.
- **Caddy**: path-based routing. `/` and `/nagios` → Nagios Core, `/nagiosql` → NagiosQL.
- **Troubleshooting**:
  - If Nagios complains about *UNKNOWN VARIABLE* or sample object files, run:
    ```bash
    ./bin/nagios-cfg-sanitize.sh
    docker compose restart nagios
    ```
  - If NagiosQL says PEAR missing, re-run: `./bin/bootstrap-pear.sh`.

---

## Structure

```
.
├── docker-compose.yml
├── .env.example
├── bin/
│   ├── bootstrap-pear.sh
│   ├── db-prepare.sh
│   ├── nagios-cfg-sanitize.sh
│   └── checks.sh
├── caddy/Caddyfile
├── nagiosql-apache/servername.conf
├── nagiosql-apache/nagiosql-alias.conf
├── nagiosql-php/zz-pear.ini
├── ssmtp/{ssmtp.conf.example,revaliases.example}
├── plugins/README.md
└── secrets/ (README + .gitignore; real secret files are local)
```

Enjoy! 🚀
