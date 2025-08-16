\
    #!/usr/bin/env bash
    set -euo pipefail
    docker compose exec -T nagios sh -lc '/usr/sbin/nagios -v /etc/nagios/nagios.cfg || true'
    docker compose exec -T nagiosql sh -lc 'php82 -r "echo get_include_path(),\"\\n\"; echo (include \"PEAR.php\")?\"PEAR:OK\\n\":\"PEAR:FAIL\\n\";"'
