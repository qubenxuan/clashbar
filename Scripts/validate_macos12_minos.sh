#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP:-$ROOT/dist/ClashBar.app}"
EXPECTED_MINOS="${EXPECTED_MINOS:-12.0}"

if ! command -v vtool >/dev/null 2>&1; then
  echo "vtool is required to validate Mach-O deployment targets." >&2
  exit 1
fi

extract_minos() {
  awk '$1 == "minos" { print $2; exit }'
}

validate_binary() {
  local label="$1"
  local path="$2"

  if [ ! -f "$path" ]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi

  local output
  local minos
  output="$(vtool -show-build "$path")"
  echo "$label vtool -show-build:"
  echo "$output"
  minos="$(printf '%s\n' "$output" | extract_minos)"

  if [ -z "$minos" ]; then
    echo "Unable to read minos for $label: $path" >&2
    exit 1
  fi
  if [ "$minos" != "$EXPECTED_MINOS" ]; then
    echo "$label minos is $minos, expected $EXPECTED_MINOS." >&2
    exit 1
  fi
}

validate_binary "ClashBar" "$APP/Contents/MacOS/ClashBar"
validate_binary "Proxy helper" "$APP/Contents/Library/HelperTools/com.clashbar.helper"

mihomo_payload=""
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  mihomo_payload="$candidate"
  break
done < <(find "$APP/Contents/Resources" -type f \( -name "mihomo" -o -name "mihomo.gz" \) | sort)

if [ -z "$mihomo_payload" ]; then
  echo "No bundled mihomo payload found; skipping mihomo minos validation."
  exit 0
fi

case "$mihomo_payload" in
  *.gz)
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/clashbar.mihomo.validate.XXXXXX")"
    trap 'rm -rf "$tmp_dir"' EXIT
    gunzip -c "$mihomo_payload" > "$tmp_dir/mihomo"
    chmod +x "$tmp_dir/mihomo"
    validate_binary "Bundled mihomo" "$tmp_dir/mihomo"
    ;;
  *)
    validate_binary "Bundled mihomo" "$mihomo_payload"
    ;;
esac
