#!/bin/bash
set -euo pipefail
 
OUT_FILE="system-info.json"
TMP_FILE="${OUT_FILE}.tmp"
 
# --- JSON escaping minimaliste (évite de casser le JSON) ---
json_escape() {
  # Échappe: \  "  newline  carriage-return  tab
  # (suffisant pour nos valeurs système classiques)
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# --- Model ---
MODEL="unknown"
if [ -r /sys/firmware/devicetree/base/model ]; then
  MODEL="$(tr -d '\0' < /sys/firmware/devicetree/base/model)"
fi
 
# --- OS release ---
PRETTY_NAME="unknown"
VERSION_ID="unknown"
VERSION_CODENAME="unknown"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  source /etc/os-release || true
  PRETTY_NAME="${PRETTY_NAME:-unknown}"
  VERSION_ID="${VERSION_ID:-unknown}"
  VERSION_CODENAME="${VERSION_CODENAME:-unknown}"
fi
 
# Debian version full (souvent /etc/debian_version => 13.3 etc)
DEBIAN_VERSION_FULL="unknown"
if [ -r /etc/debian_version ]; then
  DEBIAN_VERSION_FULL="$(tr -d '\n' < /etc/debian_version)"
fi

# --- Debian latest stable (via repository metadata) ---
DEBIAN_LATEST_VERSION="unknown"
DEBIAN_LATEST_CODENAME="unknown"

RELEASE_DATA="$(curl -fs https://deb.debian.org/debian/dists/stable/Release 2>/dev/null || true)"

if [ -n "${RELEASE_DATA}" ]; then
  DEBIAN_LATEST_VERSION="$(echo "${RELEASE_DATA}" | awk -F': ' '/^Version:/ {print $2; exit}')"
  DEBIAN_LATEST_CODENAME="$(echo "${RELEASE_DATA}" | awk -F': ' '/^Codename:/ {print $2; exit}')"

  DEBIAN_LATEST_VERSION="${DEBIAN_LATEST_VERSION:-unknown}"
  DEBIAN_LATEST_CODENAME="${DEBIAN_LATEST_CODENAME:-unknown}"
fi

IS_LATEST_DEBIAN=false
if [ "${VERSION_CODENAME}" = "${DEBIAN_LATEST_CODENAME}" ]; then
  IS_LATEST_DEBIAN=true
fi
 
# --- APT update status ---
APT_UPDATE_OK=true
UPGRADABLE_COUNT=0
 
if ! apt-get update -qq >/dev/null 2>&1; then
  APT_UPDATE_OK=false
fi
 
# Compte des paquets upgradables (ne modifie rien)
# On ignore l'entête de apt list --upgradable (première ligne)
UPGRADABLE_COUNT="$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
 
SYSTEM_UP_TO_DATE=false
if [ "${APT_UPDATE_OK}" = true ] && [ "${UPGRADABLE_COUNT}" = "0" ]; then
  SYSTEM_UP_TO_DATE=true
fi
 
# --- rpi-eeprom-update status ---
EEPROM_TOOL="missing"
EEPROM_CURRENT="unknown"
EEPROM_LATEST="unknown"
EEPROM_UP_TO_DATE="unknown"
 
if command -v rpi-eeprom-update >/dev/null 2>&1; then
  EEPROM_TOOL="present"
 
  EEPROM_OUT="$(rpi-eeprom-update 2>/dev/null || true)"
 
  # Parsing tolérant (sorties variables selon versions)
  EEPROM_CURRENT="$(echo "${EEPROM_OUT}" | awk -F': ' '/CURRENT:/{print $2; exit}' || true)"
  EEPROM_LATEST="$(echo "${EEPROM_OUT}" | awk -F': ' '/LATEST:/{print $2; exit}' || true)"
 
  EEPROM_CURRENT="${EEPROM_CURRENT:-unknown}"
  EEPROM_LATEST="${EEPROM_LATEST:-unknown}"
 
  if echo "${EEPROM_OUT}" | grep -qi "up to date"; then
    EEPROM_UP_TO_DATE=true
  elif echo "${EEPROM_OUT}" | grep -qi "update available"; then
    EEPROM_UP_TO_DATE=false
  else
    # Fallback: current==latest => yes
    if [ "${EEPROM_CURRENT}" != "unknown" ] && [ "${EEPROM_LATEST}" != "unknown" ] && [ "${EEPROM_CURRENT}" = "${EEPROM_LATEST}" ]; then
      EEPROM_UP_TO_DATE=true
    else
      EEPROM_UP_TO_DATE="unknown"
    fi
  fi
fi
 
NOW_ISO="$(date -Is)"
 
# --- Échappement JSON sur les champs texte ---
MODEL_ESC="$(json_escape "${MODEL}")"
PRETTY_NAME_ESC="$(json_escape "${PRETTY_NAME}")"
VERSION_ID_ESC="$(json_escape "${VERSION_ID}")"
VERSION_CODENAME_ESC="$(json_escape "${VERSION_CODENAME}")"
DEBIAN_VERSION_FULL_ESC="$(json_escape "${DEBIAN_VERSION_FULL}")"
DEBIAN_LATEST_VERSION_ESC="$(json_escape "${DEBIAN_LATEST_VERSION}")"
DEBIAN_LATEST_CODENAME_ESC="$(json_escape "${DEBIAN_LATEST_CODENAME}")"
EEPROM_CURRENT_ESC="$(json_escape "${EEPROM_CURRENT}")"
EEPROM_LATEST_ESC="$(json_escape "${EEPROM_LATEST}")"
 
# --- Écriture JSON (atomique) ---
cat > "${TMP_FILE}" <<JSON
{
  "timestamp": "$(json_escape "${NOW_ISO}")",
  "model": "${MODEL_ESC}",
  "system": {
    "pretty_name": "${PRETTY_NAME_ESC}",
    "debian_version_full": "${DEBIAN_VERSION_FULL_ESC}",
    "version_id": "${VERSION_ID_ESC}",
    "version_codename": "${VERSION_CODENAME_ESC}",
    "debian_latest": {
      "version": "${DEBIAN_LATEST_VERSION_ESC}",
      "codename": "${DEBIAN_LATEST_CODENAME_ESC}",
      "is_latest_release": ${IS_LATEST_DEBIAN}
    },
    "apt": {
      "update_ok": ${APT_UPDATE_OK},
      "upgradable_count": ${UPGRADABLE_COUNT},
      "up_to_date": ${SYSTEM_UP_TO_DATE}
    }
  },
  "rpi_eeprom": {
    "tool": "${EEPROM_TOOL}",
    "current": "${EEPROM_CURRENT_ESC}",
    "latest": "${EEPROM_LATEST_ESC}",
    "up_to_date": ${EEPROM_UP_TO_DATE}
  }
}
JSON

chmod 0644 "${TMP_FILE}"
mv -f "${TMP_FILE}" "${OUT_FILE}"
