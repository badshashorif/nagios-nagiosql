\
    #!/usr/bin/env bash
    set -euo pipefail
    # Ensure DB/schema and grant matrix for the NagiosQL installer.
    comp="${COMPOSE_CMD:-docker compose}"
    HN="$($comp exec -T nagiosql hostname)"
    $comp exec -T db sh -lc '
      RP=$(cat /run/secrets/db-root-password)
      UP=$(cat /run/secrets/nagiosql-db-password)
      mariadb -uroot -p"$RP" <<SQL
    CREATE DATABASE IF NOT EXISTS nagiosql CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS "nagiosql"@"%"        IDENTIFIED BY "$UP";
    CREATE USER IF NOT EXISTS "nagiosql"@"localhost" IDENTIFIED BY "$UP";
    CREATE USER IF NOT EXISTS "nagiosql"@"db"        IDENTIFIED BY "$UP";
    GRANT ALL PRIVILEGES ON nagiosql.* TO "nagiosql"@"%";
    GRANT ALL PRIVILEGES ON nagiosql.* TO "nagiosql"@"localhost";
    GRANT ALL PRIVILEGES ON nagiosql.* TO "nagiosql"@"db";
    FLUSH PRIVILEGES;
    SQL
    '
    echo ">> DB and grants prepared."
