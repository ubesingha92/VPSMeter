#!/usr/bin/env bash
# ==============================================================================
# check-endpoints.sh - Endpoint health check for vpsmeter.sh
# ==============================================================================
# Verifies that every download_benchmark URL in vpsmeter.sh is active,
# returns HTTP 2xx, and yields >100 KB payload within 10 seconds.
#
# Usage:
#   bash check-endpoints.sh [options] [path/to/vpsmeter.sh]
#
# Options:
#   -4, --ipv4-only      Test only IPv4 endpoints
#   -6, --strict-ipv6    Force testing IPv6 even if host lacks IPv6 connectivity
#   -h, --help           Show this help message
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT=""
IPV4_ONLY=0
STRICT_IPV6=0

show_help() {
    cat <<'EOF'
Usage: bash check-endpoints.sh [OPTIONS] [PATH_TO_VPSMETER.SH]

Options:
  -4, --ipv4-only     Only verify IPv4 endpoints (skip IPv6)
  -6, --strict-ipv6   Enforce IPv6 tests even if local host has no IPv6 route
  -h, --help          Show this help message

Examples:
  bash check-endpoints.sh
  bash check-endpoints.sh --ipv4-only
  bash check-endpoints.sh /custom/path/vpsmeter.sh
EOF
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -4|--ipv4-only)
            IPV4_ONLY=1
            shift
            ;;
        -6|--strict-ipv6)
            STRICT_IPV6=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            printf 'Error: Unknown option: %s\n' "$1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            if [ -z "$TARGET_SCRIPT" ]; then
                TARGET_SCRIPT="$1"
            else
                printf 'Error: Unexpected argument: %s\n' "$1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET_SCRIPT" ]; then
    TARGET_SCRIPT="${SCRIPT_DIR}/vpsmeter.sh"
fi

if [ ! -f "$TARGET_SCRIPT" ]; then
    printf 'Error: Benchmark script not found: %s\n' "$TARGET_SCRIPT" >&2
    exit 1
fi

# Detect local IPv6 connectivity
HAS_IPV6=0
if [ "$IPV4_ONLY" -eq 0 ]; then
    if curl -6 -fsSL --connect-timeout 3 --max-time 5 -o /dev/null https://speed.cloudflare.com/ 2>/dev/null || \
       curl -6 -fsSL --connect-timeout 3 --max-time 5 -o /dev/null http://icanhazip.com/ 2>/dev/null; then
        HAS_IPV6=1
    fi
fi

# Determine terminal color support
USE_COLOR=0
if [ -t 1 ]; then
    USE_COLOR=1
fi

col_green=""
col_red=""
col_yellow=""
col_reset=""
if [ "$USE_COLOR" -eq 1 ]; then
    col_green="$(printf '\033[32m')"
    col_red="$(printf '\033[31m')"
    col_yellow="$(printf '\033[33m')"
    col_reset="$(printf '\033[0m')"
fi

format_bytes() {
    local bytes="$1"
    awk -v b="$bytes" '
    BEGIN {
        if (b >= 1048576) {
            printf "%.2f MB", b / 1048576
        } else if (b >= 1024) {
            printf "%.1f KB", b / 1024
        } else {
            printf "%d B", b
        }
    }'
}

printf 'VPSMeter Endpoint Health Check\n'
printf 'Target: %s\n' "$TARGET_SCRIPT"
if [ "$IPV4_ONLY" -eq 1 ]; then
    printf 'IPv6:   Disabled (--ipv4-only)\n'
elif [ "$HAS_IPV6" -eq 1 ]; then
    printf 'IPv6:   Available on host\n'
else
    printf 'IPv6:   Not available on host (skipping IPv6 targets)\n'
fi
printf '%s\n' '--------------------------------------------------------------------------------'

total=0
passed=0
failed=0
skipped=0

while read -r flag url; do
    [ -z "$flag" ] && continue
    total=$((total + 1))

    # Skip IPv6 if disabled or host has no IPv6 connectivity (unless strict requested)
    if [ "$flag" = "-6" ]; then
        if [ "$IPV4_ONLY" -eq 1 ] || { [ "$HAS_IPV6" -eq 0 ] && [ "$STRICT_IPV6" -eq 0 ]; }; then
            skipped=$((skipped + 1))
            printf '[%sSKIP%s] %-2s %-54s -> Skipped (no local IPv6)\n' "$col_yellow" "$col_reset" "$flag" "$url"
            continue
        fi
    fi

    # Perform health request (follow redirects, max 10s, connect timeout 4s)
    out=$(curl -L -s -o /dev/null -w '%{http_code} %{size_download} %{time_total}' --connect-timeout 4 --max-time 10 "$flag" "$url" 2>/dev/null)
    http=$(printf '%s' "$out" | awk '{print $1}')
    size=$(printf '%s' "$out" | awk '{print $2}')
    time_taken=$(printf '%s' "$out" | awk '{print $3}')

    http="${http:-000}"
    size="${size:-0}"
    time_taken="${time_taken:-0.000}"
    size_fmt=$(format_bytes "$size")

    case "$http" in
        2*)
            if [ "$size" -gt 100000 ]; then
                passed=$((passed + 1))
                printf '[%sPASS%s] %-2s %-54s -> HTTP %s, %10s in %4.1fs\n' \
                    "$col_green" "$col_reset" "$flag" "$url" "$http" "$size_fmt" "$time_taken"
            else
                failed=$((failed + 1))
                printf '[%sFAIL%s] %-2s %-54s -> HTTP %s (payload too small: %s)\n' \
                    "$col_red" "$col_reset" "$flag" "$url" "$http" "$size_fmt"
            fi
            ;;
        *)
            failed=$((failed + 1))
            printf '[%sFAIL%s] %-2s %-54s -> HTTP %s (curl error / unresponsive)\n' \
                "$col_red" "$col_reset" "$flag" "$url" "$http"
            ;;
    esac
done <<EOF
$(grep -Eo 'download_benchmark -[46] [^ ]+' "$TARGET_SCRIPT" | tr -d '\r' | awk '{ print $2, $3 }')
EOF

printf '%s\n' '--------------------------------------------------------------------------------'
printf 'Summary: %d total, %d passed, %d failed, %d skipped\n' "$total" "$passed" "$failed" "$skipped"

if [ "$failed" -eq 0 ]; then
    printf '%sAll active endpoints healthy!%s\n' "$col_green" "$col_reset"
    exit 0
else
    printf '%s%d endpoint(s) failed health check.%s\n' "$col_red" "$failed" "$col_reset"
    exit 1
fi
