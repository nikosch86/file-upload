#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="file-upload-test"
PORT=18024
BASE_URL="http://127.0.0.1:${PORT}"
TTL_PORT=18025
TTL_URL="http://127.0.0.1:${TTL_PORT}"
COMPOSE="docker compose -p ${PROJECT} -f ${ROOT_DIR}/tests/compose.yaml"
TEST_DIR="$(mktemp -d -t file-upload-e2e.XXXXXX)"

red()   { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
info()  { printf '\033[0;36m%s\033[0m\n' "$*"; }

cleanup() {
  info "==> Tearing down test environment"
  ${COMPOSE} down -v >/dev/null 2>&1 || true
  rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

fail() { red "FAIL: $*"; exit 1; }

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "${expected}" != "${actual}" ]; then
    red "FAIL: ${msg}"
    red "  expected: ${expected}"
    red "  actual:   ${actual}"
    exit 1
  fi
}

assert_match() {
  local pattern="$1" actual="$2" msg="$3"
  if ! echo "${actual}" | grep -qE "${pattern}"; then
    red "FAIL: ${msg}"
    red "  pattern: ${pattern}"
    red "  actual:  ${actual}"
    exit 1
  fi
}

upload() {
  local file="$1"
  local name="${2:-}"
  local exp="${3:-}"
  local query=""
  [ -n "${exp}" ] && query="?exp=${exp}"
  if [ -n "${name}" ]; then
    curl -sf -F "file=@${file};filename=${name}" "${BASE_URL}/${query}"
  else
    curl -sf -F "file=@${file}" "${BASE_URL}/${query}"
  fi
}

# Upload against an arbitrary base URL (used for the retention-enabled instance).
upload_to() {
  local base="$1" file="$2" exp="${3:-}"
  local query=""
  [ -n "${exp}" ] && query="?exp=${exp}"
  curl -sf -F "file=@${file}" "${base}/${query}"
}

marker_ts() {
  local hex="$1"
  ${COMPOSE} exec -T server bash -c "ls /var/www/dl/${hex}/expires-at-* 2>/dev/null | head -1" \
    | tr -d '\r\n' | sed -E 's|.*expires-at-([0-9]+).*|\1|'
}

assert_near() {
  local expected="$1" actual="$2" tolerance="$3" msg="$4"
  local diff
  diff=$(abs $(( actual - expected )))
  if [ "${diff}" -gt "${tolerance}" ]; then
    red "FAIL: ${msg}"
    red "  expected: ~${expected} (tolerance ${tolerance})"
    red "  actual:   ${actual}"
    exit 1
  fi
}

to_local_url() { echo "$1" | sed -E "s|^https?://[^/]+|${BASE_URL}|"; }
extract_hex()  { echo "$1" | sed -E 's|.*/dl/([a-f0-9]+)/.*|\1|'; }
extract_name() { echo "$1" | sed -E 's|.*/dl/[a-f0-9]+/(.*)$|\1|'; }

abs() { local n=$1; echo "${n#-}"; }

info "==> Cleaning previous test environment"
${COMPOSE} down -v >/dev/null 2>&1 || true

info "==> Building images"
${COMPOSE} build

info "==> Starting test stack"
${COMPOSE} up -d

info "==> Waiting for server"
for i in $(seq 1 30); do
  if curl -sf "${BASE_URL}/" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -sf "${BASE_URL}/" >/dev/null || fail "server failed to start"

for i in $(seq 1 30); do
  if curl -sf "${TTL_URL}/" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -sf "${TTL_URL}/" >/dev/null || fail "retention server failed to start"

# === Test 1: Basic upload + download round-trip ===
info "Test 1: basic upload + download"
echo "hello world" > "${TEST_DIR}/test.txt"
URL=$(upload "${TEST_DIR}/test.txt")
assert_match '^https?://[^/]+/dl/[a-f0-9]{32}/test\.txt$' "${URL}" "URL format"

LOCAL_URL=$(to_local_url "${URL}")
DOWNLOADED=$(curl -sf "${LOCAL_URL}")
assert_eq "hello world" "${DOWNLOADED}" "downloaded content matches"

# === Test 2: Security headers on /dl/ ===
info "Test 2: Content-Disposition + X-Content-Type-Options headers"
HEADERS=$(curl -sfI "${LOCAL_URL}")
assert_match 'Content-Disposition:[[:space:]]*attachment'    "${HEADERS}" "Content-Disposition: attachment"
assert_match 'X-Content-Type-Options:[[:space:]]*nosniff'    "${HEADERS}" "X-Content-Type-Options: nosniff"

# === Test 3: Extensionless filename also gets headers ===
info "Test 3: extensionless filename"
echo "no ext content" > "${TEST_DIR}/noext"
URL=$(upload "${TEST_DIR}/noext")
assert_eq "noext" "$(extract_name "${URL}")" "extensionless filename preserved"
HEADERS=$(curl -sfI "$(to_local_url "${URL}")")
assert_match 'Content-Disposition:[[:space:]]*attachment' "${HEADERS}" "extensionless still gets Content-Disposition"

# === Test 4: Leading-dot filename is stripped ===
info "Test 4: leading dots stripped (.htaccess -> htaccess)"
echo "secret" > "${TEST_DIR}/dotfile"
URL=$(upload "${TEST_DIR}/dotfile" ".htaccess")
assert_eq "htaccess" "$(extract_name "${URL}")" "leading dot stripped"

# === Test 5: Special characters sanitized ===
info "Test 5: unsafe characters replaced"
URL=$(upload "${TEST_DIR}/test.txt" "evil file<>name.txt")
assert_eq "evil_file__name.txt" "$(extract_name "${URL}")" "unsafe chars replaced"

# === Test 6: Each expiry unit produces a roughly-correct expires-at marker ===
info "Test 6: expiry units (h/d/w/m/y) compute correct timestamps"
for unit in h d w m y; do
  NOW=$(date +%s)
  URL=$(upload "${TEST_DIR}/test.txt" "" "1${unit}")
  HEX=$(extract_hex "${URL}")
  MARKER=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl/${HEX}/expires-at-* 2>/dev/null | head -1" | tr -d '\r\n')
  [ -n "${MARKER}" ] || fail "no expires-at marker for unit ${unit}"
  TS=$(echo "${MARKER}" | sed -E 's|.*expires-at-([0-9]+).*|\1|')
  case "${unit}" in
    h) EXPECTED=3600       ;;
    d) EXPECTED=86400      ;;
    w) EXPECTED=604800     ;;
    m) EXPECTED=$((24 * 3600 * 305 / 10)) ;;  # 30.5 days
    y) EXPECTED=$((24 * 3600 * 365))      ;;
  esac
  DELTA=$(( TS - NOW ))
  DIFF=$(abs $(( DELTA - EXPECTED )))
  TOLERANCE=$(( EXPECTED / 100 + 60 ))  # 1% + 60s slack for build/exec latency
  if [ "${DIFF}" -gt "${TOLERANCE}" ]; then
    fail "unit ${unit}: TS-NOW=${DELTA}, expected ~${EXPECTED}, diff ${DIFF} > ${TOLERANCE}"
  fi
done

# === Test 7: Invalid exp is rejected, and stores nothing ===
info "Test 7: invalid exp returns 400 and leaves no directory behind"
BEFORE=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl | wc -l" | tr -d '\r\n')
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -F "file=@${TEST_DIR}/test.txt" "${BASE_URL}/?exp=garbage")
assert_eq "400" "${HTTP_CODE}" "invalid exp rejected with 400"
AFTER=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl | wc -l" | tr -d '\r\n')
assert_eq "${BEFORE}" "${AFTER}" "rejected upload created no directory"

# === Test 7b: Absurd exp values cannot overflow into a permanent upload ===
# An unbounded duration wraps the timestamp negative, and a marker like
# "expires-at--7932..." never matches cron's ^expires-at-([0-9]+)$, so the upload
# would outlive any TTL.
info "Test 7b: overflowing exp values are rejected"
for bad in 99999999999999y 999999999999999999999y 0y; do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -F "file=@${TEST_DIR}/test.txt" "${BASE_URL}/?exp=${bad}")
  [ "${HTTP_CODE}" = "400" ] || fail "exp=${bad} returned ${HTTP_CODE}, expected 400"
done
NEGATIVE=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl/*/expires-at--* 2>/dev/null | wc -l" | tr -d '\r\n')
assert_eq "0" "${NEGATIVE}" "no unparseable negative marker was ever written"

# === Test 7c: An exp cookie must not affect uploads ===
info "Test 7c: stray exp cookie is ignored, not rejected"
URL=$(curl -sf -b 'exp=garbage' -F "file=@${TEST_DIR}/test.txt" "${BASE_URL}/")
assert_match '/dl/[a-f0-9]{32}/test\.txt$' "${URL}" "upload succeeds despite an exp cookie"

# === Test 8: Cron deletes expired uploads ===
info "Test 8: cron deletes expired upload"
URL=$(upload "${TEST_DIR}/test.txt" "" "1h")
HEX=$(extract_hex "${URL}")
LOCAL_URL=$(to_local_url "${URL}")
curl -sf "${LOCAL_URL}" >/dev/null || fail "uploaded file not retrievable"

# Backdate the marker (1 = 1970-01-01 00:00:01)
${COMPOSE} exec -T server bash -c "cd /var/www/dl/${HEX} && mv expires-at-* expires-at-1"

# Run cron sweep manually
${COMPOSE} exec -T cron /run-cron.sh >/dev/null 2>&1

if ${COMPOSE} exec -T server bash -c "[ -d /var/www/dl/${HEX} ]" 2>/dev/null; then
  fail "expired upload directory still present after cron"
fi

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${LOCAL_URL}")
[ "${HTTP_CODE}" = "404" ] || fail "expected 404 for deleted upload, got ${HTTP_CODE}"

# === Test 9: Cron preserves files without expiry ===
info "Test 9: cron preserves non-expiring files"
URL=$(upload "${TEST_DIR}/test.txt")
LOCAL_URL=$(to_local_url "${URL}")
${COMPOSE} exec -T cron /run-cron.sh >/dev/null 2>&1
curl -sf "${LOCAL_URL}" >/dev/null || fail "non-expiring file removed by cron"

# === Test 10: Cron preserves not-yet-expired files ===
info "Test 10: cron preserves files with future expiry"
URL=$(upload "${TEST_DIR}/test.txt" "" "1y")
LOCAL_URL=$(to_local_url "${URL}")
${COMPOSE} exec -T cron /run-cron.sh >/dev/null 2>&1
curl -sf "${LOCAL_URL}" >/dev/null || fail "future-expiry file removed by cron"

# === Test 11: No DEFAULT_EXPIRY means uploads stay permanent ===
info "Test 11: without DEFAULT_EXPIRY no marker is written"
URL=$(upload "${TEST_DIR}/test.txt")
HEX=$(extract_hex "${URL}")
COUNT=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl/${HEX}/ 2>/dev/null | grep -c '^expires-at-' || true" | tr -d '\r\n')
assert_eq "0" "${COUNT}" "no default expiry produces no marker"

# === Test 12: DEFAULT_EXPIRY applies when exp is absent ===
info "Test 12: DEFAULT_EXPIRY=1d applies to an upload with no exp"
NOW=$(date +%s)
URL=$(upload_to "${TTL_URL}" "${TEST_DIR}/test.txt")
HEX=$(extract_hex "${URL}")
TS=$(marker_ts "${HEX}")
[ -n "${TS}" ] || fail "default expiry wrote no marker"
assert_near 86400 $(( TS - NOW )) 120 "default expiry is ~1 day out"

# === Test 13: An explicit exp overrides the default ===
info "Test 13: explicit exp wins over DEFAULT_EXPIRY"
NOW=$(date +%s)
URL=$(upload_to "${TTL_URL}" "${TEST_DIR}/test.txt" "1h")
HEX=$(extract_hex "${URL}")
TS=$(marker_ts "${HEX}")
assert_near 3600 $(( TS - NOW )) 120 "explicit 1h overrides the 1d default"

# === Test 14: A bad DEFAULT_EXPIRY stops the container starting ===
info "Test 14: invalid DEFAULT_EXPIRY fails fast"
if ${COMPOSE} run --rm -e DEFAULT_EXPIRY=garbage server >/dev/null 2>&1; then
  fail "container started despite an invalid DEFAULT_EXPIRY"
fi

# === Test 15: Pre-existing unmarked uploads survive a sweep ===
# A directory with no marker is permanent: DEFAULT_EXPIRY is written at upload
# time, so it never applies retroactively to what is already on disk.
info "Test 15: legacy unmarked directories are never swept"
${COMPOSE} exec -T server bash -c "mkdir -p /var/www/dl/deadbeef && echo legacy > /var/www/dl/deadbeef/old.txt && touch -d '2 years ago' /var/www/dl/deadbeef /var/www/dl/deadbeef/old.txt"
${COMPOSE} exec -T cron /run-cron.sh >/dev/null 2>&1
${COMPOSE} exec -T server bash -c "[ -f /var/www/dl/deadbeef/old.txt ]" \
  || fail "legacy unmarked upload was deleted by cron"

# === Test 16: TRUSTED_PROXIES honours several ranges ===
info "Test 16: X-Forwarded-For is trusted from the docker bridge range"
curl -sf -H 'X-Forwarded-For: 203.0.113.7' -F "file=@${TEST_DIR}/test.txt" "${TTL_URL}/" >/dev/null
LOGS=$(${COMPOSE} logs server_ttl 2>&1)
assert_match '203\.0\.113\.7' "${LOGS}" "real client IP recorded via trusted proxy range"

# Control: the default instance does not trust the bridge, so it must ignore the header.
curl -sf -H 'X-Forwarded-For: 198.51.100.9' -F "file=@${TEST_DIR}/test.txt" "${BASE_URL}/" >/dev/null
LOGS=$(${COMPOSE} logs server 2>&1)
if echo "${LOGS}" | grep -qE '198\.51\.100\.9'; then
  fail "default TRUSTED_PROXIES wrongly trusted X-Forwarded-For from an untrusted range"
fi

green "==> All e2e tests passed"
