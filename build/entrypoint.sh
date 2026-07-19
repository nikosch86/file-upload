#!/bin/bash
set -euo pipefail

set -f  # the proxy list is split on whitespace below, never globbed

DEFAULT_EXPIRY="${DEFAULT_EXPIRY:-}"
TRUSTED_PROXIES="${TRUSTED_PROXIES:-192.168.0.0/16}"

# Fail fast on a bad retention setting rather than silently serving without one.
if [ -n "${DEFAULT_EXPIRY}" ] && ! [[ ${DEFAULT_EXPIRY} =~ ^[0-9]+[hdwmy]$ ]]; then
  echo "FATAL: DEFAULT_EXPIRY='${DEFAULT_EXPIRY}' is not a valid duration (<number><h|d|w|m|y>, for example 30d)" >&2
  exit 1
fi

for cidr in ${TRUSTED_PROXIES}; do
  if ! [[ ${cidr} =~ ^[0-9a-fA-F.:]+(/[0-9]+)?$ ]]; then
    echo "FATAL: TRUSTED_PROXIES entry '${cidr}' is not an IP or CIDR range" >&2
    exit 1
  fi
done

{
  echo 'RemoteIPHeader X-Forwarded-For'
  for cidr in ${TRUSTED_PROXIES}; do
    echo "RemoteIPInternalProxy ${cidr}"
  done
  echo 'LogFormat "%a %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined'
  # SetEnv puts this in $_SERVER for mod_php; getenv() is the fallback.
  echo "SetEnv DEFAULT_EXPIRY \"${DEFAULT_EXPIRY}\""
} > /etc/apache2/conf-enabled/reverse-proxy.conf

exec "$@"
