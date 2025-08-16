This directory holds **local secrets** used by Docker secrets. Do not commit these to Git.

Required files:
  - db-root-password           (strong password for MariaDB root)
  - nagiosql-db-password       (password for DB user 'nagiosql')
  - nagios-htpasswd            (htpasswd file containing UI users listed in NAGIOS_AUTH_USERS)

Quick start:
  printf '%s' 'SuperSecretRoot!' > secrets/db-root-password
  printf '%s' 'AnotherSecret!'   > secrets/nagiosql-db-password
  docker run --rm httpd:2.4-alpine htpasswd -nbB nagiosadmin 'ChangeMe123' > secrets/nagios-htpasswd
