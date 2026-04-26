#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="file-upload-test"
PORT=18024
BASE_URL="http://127.0.0.1:${PORT}"
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

to_local_url() { echo "$1" | sed -E "s|^https://[^/]+|${BASE_URL}|"; }
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

# === Test 1: Basic upload + download round-trip ===
info "Test 1: basic upload + download"
echo "hello world" > "${TEST_DIR}/test.txt"
URL=$(upload "${TEST_DIR}/test.txt")
assert_match '^https://[^/]+/dl/[a-f0-9]{32}/test\.txt$' "${URL}" "URL format"

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

# === Test 7: Invalid exp is silently ignored ===
info "Test 7: invalid exp does not create marker"
URL=$(upload "${TEST_DIR}/test.txt" "" "garbage")
HEX=$(extract_hex "${URL}")
COUNT=$(${COMPOSE} exec -T server bash -c "ls /var/www/dl/${HEX}/ 2>/dev/null | grep -c '^expires-at-' || true" | tr -d '\r\n')
assert_eq "0" "${COUNT}" "invalid exp produces no marker"

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

green "==> All e2e tests passed"
