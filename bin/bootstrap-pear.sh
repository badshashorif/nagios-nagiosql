\
    #!/usr/bin/env bash
    set -euo pipefail
    # Bootstraps PEAR into the named volume used by the nagiosql container.
    vol="nagios-onehost_nagiosql-pear"
    # If you're not in a compose project directory, create volume name without prefix
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
      # try bare name
      vol="nagiosql-pear"
      docker volume inspect "$vol" >/dev/null 2>&1 || docker volume create "$vol" >/dev/null
    fi

    echo ">> Using PEAR volume: $vol"
    docker run --rm -v "$vol:/usr/share/pear" --entrypoint sh instantlinux/nagiosql:latest -lc '
      set -e
      apk add --no-cache curl php82-cli >/dev/null
      php82 -r "copy(\"https://pear.php.net/go-pear.phar\",\"/tmp/go-pear.phar\");"
      # install to /usr/local/pear then copy to the mounted volume (/usr/share/pear)
      yes "" | php82 /tmp/go-pear.phar >/dev/null 2>&1 || true
      if [ -d /usr/local/pear ]; then
        mkdir -p /usr/share/pear
        cp -a /usr/local/pear/* /usr/share/pear/
      fi
      [ -f /usr/share/pear/PEAR.php ] && echo "PEAR.php present" || (echo "PEAR install failed" >&2; exit 1)
    '
    echo ">> PEAR bootstrap complete."
