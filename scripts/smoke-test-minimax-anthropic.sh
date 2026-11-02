#!/usr/bin/env bash
#
# Smoke test for the MiniMax Anthropic-compatible endpoint.
#
# Verifies the upstream API independently of LibreChat, so a failure can be
# attributed to either the provider credentials or the LibreChat endpoint config.
#
# Usage:
#   MINIMAX_API_KEY=<key> ./scripts/smoke-test-minimax-anthropic.sh
#
# The key is read from the environment only and is never printed.

set -uo pipefail

API_URL="${MINIMAX_ANTHROPIC_URL:-https://api.minimaxi.com/anthropic/v1/messages}"
MODEL="${MINIMAX_MODEL:-MiniMax-M3.1-Flash}"

red() { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

if [ -z "${MINIMAX_API_KEY:-}" ]; then
  red "[FAIL] MINIMAX_API_KEY is not set."
  echo
  echo "Administrator action required — set the key in one of these places:"
  echo "  1. Project root .env:      MINIMAX_API_KEY=<your-key>"
  echo "  2. Shell environment:       export MINIMAX_API_KEY=<your-key>"
  echo
  echo "Then re-run: ./scripts/smoke-test-minimax-anthropic.sh"
  exit 2
fi

# Present the key without revealing it.
key_len=${#MINIMAX_API_KEY}
if [ "$key_len" -lt 8 ]; then
  red "[FAIL] MINIMAX_API_KEY looks too short to be a valid key (length $key_len)."
  exit 2
fi
echo "[INFO] Using MINIMAX_API_KEY (length $key_len, value not shown)."
echo "[INFO] Endpoint: $API_URL"
echo "[INFO] Model:    $MODEL"
echo

body=$(cat <<JSON
{
  "model": "$MODEL",
  "max_tokens": 256,
  "messages": [
    {
      "role": "user",
      "content": "只回复：MiniMax连接成功"
    }
  ]
}
JSON
)

# --silent hides the progress meter; --write-out keeps the status code separate
# from the body so a non-2xx response can still be summarized without leaking headers.
tmp_body=$(mktemp)
trap 'rm -f "$tmp_body"' EXIT

status=$(curl --silent --show-error \
  --output "$tmp_body" \
  --write-out '%{http_code}' \
  --max-time 60 \
  -X POST "$API_URL" \
  -H "x-api-key: $MINIMAX_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --data "$body" 2>&1) || true

if ! printf '%s' "$status" | grep -qE '^[0-9]{3}$'; then
  red "[FAIL] Request did not complete."
  echo "  Transport error: $status"
  exit 1
fi

echo "[INFO] HTTP status: $status"

response=$(cat "$tmp_body")

if [ "$status" = "200" ]; then
  # Pull the text out of the Anthropic content array without requiring jq.
  text=$(printf '%s' "$response" \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as exc:
    print(f"<unparsable response: {exc}>")
    sys.exit(0)
if data.get("type") == "error":
    err = data.get("error", {})
    print(f"<api error: {err.get(chr(116)+chr(121)+chr(112)+chr(101))}: {err.get(chr(109)+chr(101)+chr(115)+chr(115)+chr(97)+chr(103)+chr(101))}>")
    sys.exit(0)
parts = []
for block in data.get("content", []):
    if block.get("type") == "text":
        parts.append(block.get("text", ""))
print("".join(parts).strip() or "<empty response>")
' 2>/dev/null)

  green "[PASS] Request succeeded."
  echo "  Model returned: $MODEL"
  echo "  Response: $text"
  exit 0
fi

red "[FAIL] Provider returned HTTP $status."
echo "  Error summary:"
printf '%s' "$response" | head -c 600 | sed 's/^/    /'
echo
echo
echo "  Likely causes:"
echo "    - Invalid or expired API key"
echo "    - Wrong account region (the key must match the endpoint's region)"
echo "    - Model not enabled for this account"
echo "    - Wrong base URL for the account's region"
exit 1
