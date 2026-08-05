#!/bin/bash

# OVPN config selection for haugene/docker-transmission-openvpn.
# Configs (including default.ovpn) are fetched from this repo by
# fetch-external-configs.sh; this script only maps OVPN_* env vars.
#
# Precedence:
#   1. OPENVPN_CONFIG already set → leave alone
#   2. Any OVPN_* set → build OPENVPN_CONFIG as connection.country.city.protocol
#   3. Neither → leave alone; start.sh uses committed default.ovpn

if [[ -z "${VPN_PROVIDER_HOME:-}" ]]; then
  echo "ERROR: Need to have VPN_PROVIDER_HOME set to call this script" && exit 1
fi

# User already chose a config by name; do not override.
if [[ -n "${OPENVPN_CONFIG:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

if [[ -n "${OVPN_CONNECTION:-}" || -n "${OVPN_PROTOCOL:-}" || -n "${OVPN_COUNTRY:-}" || -n "${OVPN_CITY:-}" ]]; then
  OPENVPN_CONFIG="${OVPN_CONNECTION}.${OVPN_COUNTRY}.${OVPN_CITY}.${OVPN_PROTOCOL}"
  if [[ ! -f "${VPN_PROVIDER_HOME}/${OPENVPN_CONFIG}.ovpn" ]]; then
    echo "ERROR: No OVPN config matching ${OPENVPN_CONFIG}.ovpn"
    echo "Built from OVPN_CONNECTION=${OVPN_CONNECTION:-} OVPN_COUNTRY=${OVPN_COUNTRY:-} OVPN_CITY=${OVPN_CITY:-} OVPN_PROTOCOL=${OVPN_PROTOCOL:-}"
    echo "Available configs:"
    # shellcheck disable=SC2010
    ls "${VPN_PROVIDER_HOME}" | grep '\.ovpn$' || true
    echo "NB: Set all OVPN_* vars, or use OPENVPN_CONFIG=<name-without-.ovpn>, or omit both for default.ovpn."
    exit 1
  fi
  export OPENVPN_CONFIG
  echo "Selected OVPN config from OVPN_* vars: ${OPENVPN_CONFIG}.ovpn"
fi
