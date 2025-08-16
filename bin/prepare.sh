\
    #!/usr/bin/env bash
    set -euo pipefail
    cp -n .env.example .env || true
    mkdir -p secrets ssmtp plugins
    echo ">> Remember to fill secrets/ and ssmtp/ files before 'docker compose up -d'"
