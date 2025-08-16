\
    #!/usr/bin/env bash
    set -euo pipefail
    # Comment out problematic sample lines in nagios.cfg if present.
    docker compose exec -T nagios sh -lc '
      set -e
      CFG=/etc/nagios/nagios.cfg
      cp "$CFG" "$CFG.sanitize.$(date +%s)"
      # comment old sample cfg_file entries (printer/windows/switch etc.)
      sed -i -E "s#^cfg_file=/etc/nagios/objects/(windows|switch|printer|contactgroups|contacts|contacttemplates|hostdependencies|hostescalations|hostextinfo|hostgroups|servicegroups|servicedependencies|serviceescalations|serviceextinfo|servicetemplates|hosttemplates)\\.cfg#; &#" "$CFG"
      # comment legacy perfdata directives if prefixed with ; (make it #)
      sed -i -E "s#^;([hs]ost_perfdata_)#\\# \\1#" "$CFG" || true
      echo "Patched: $CFG"
    '
