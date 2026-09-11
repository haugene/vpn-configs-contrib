#!/bin/bash
#
# Port forwarding for PIA's next-generation network.
#
# This follows PIA's own port_forwarding.sh and get_token.sh from
# https://github.com/pia-foss/manual-connections, which is the reference
# implementation of the protocol:
#
#   1. Authenticate against the PIA website to get an account token.
#   2. Ask the VPN server's port forwarding API for a signature. It answers
#      with a base64 "payload" (the port and an expiry, roughly two months
#      out) and a "signature" proving the payload came from PIA.
#   3. Replay that payload and signature to bindPort at least every 15
#      minutes. The servers keep no record of your activity, so a port that
#      stops getting keepalives is simply dropped.
#
# Payload plus signature *is* the reservation: it is not tied to the server
# that issued it, so we cache it and reuse it across container restarts
# instead of burning a new port every time. PIA exposes the same idea as the
# PAYLOAD_AND_SIGNATURE variable in port_forwarding.sh. Set PIA_PF_REUSE=false
# to skip the cache and take a new port on every start.
#
# All API calls verify TLS the way PIA's script does. The API presents a
# certificate whose common name is the server's "cn" from the server list,
# signed by the RSA-4096 CA shipped alongside this script. Since the API is
# addressed by IP, curl is pointed at the address with --connect-to while
# still verifying the name.
#
# configure-openvpn.sh records the server's cn and region in the generated
# config as "; pia_cn" and "; pia_region" lines, which is where the name to
# verify against comes from.

set -o pipefail

source /etc/openvpn/utils.sh

# shellcheck source=/dev/null
. /etc/transmission/environment-variables.sh

##
# Constants and configuration
##

readonly PF_API_PORT=19999
readonly PF_BIND_INTERVAL=900               # PIA drops a port with no keepalive after ~15 minutes
readonly PF_RENEW_MARGIN=$((60 * 60 * 24))  # renew the reservation a day before it expires
readonly PF_TOKEN_URL="https://www.privateinternetaccess.com/api/client/v2/token"

readonly CURL_MAX_TIME=15
readonly CURL_RETRIES=5
readonly CURL_RETRY_DELAY=15

readonly OPENVPN_CREDENTIALS=/config/openvpn-credentials.txt
readonly TRANSMISSION_CREDENTIALS=/config/transmission-credentials.txt

# Cached reservation, on the /config volume so it survives a restart. May be
# overridden by the settings file configure-openvpn.sh writes; see below.
PF_STATE_FILE="${PIA_PF_STATE_FILE:-/config/pia-nextgen-portforward.json}"

# Set to false to not cache the reservation at all, so every container start
# asks PIA for a new port instead of picking the old one back up.
PIA_PF_REUSE="${PIA_PF_REUSE:-true}"

# Set to true to skip certificate verification. Only useful if PIA changes
# what the port forwarding API presents; it is not a supported configuration.
PIA_PF_INSECURE="${PIA_PF_INSECURE:-false}"

# Populated as we go.
provider_home=""      # directory holding the configs, the CA and the settings
pf_cn=""              # server common name, verified against the API certificate
pf_region=""          # region id, only used to make error messages actionable
pf_gateway=""         # VPN gateway address
pf_api_ip=""          # address the port forwarding API answers on
pf_api_host=""        # host used in the API URL (the cn, unless verification is off)
pf_curl_tls=()        # TLS options shared by every API call

pf_token=""
pf_payload=""
pf_signature=""
pf_port=""
pf_expires_at=""      # seconds since epoch

##
# Helpers
##

require_tools() {
  local cmd
  for cmd in curl jq ip base64 date transmission-remote; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fatal_error "PIA: $cmd is required for port forwarding but was not found"
    fi
  done
}

# Flatten a value onto a single line before it goes into a message. API bodies
# can contain real newlines, and utils.sh logs with printf "%b", which would
# also turn a literal backslash-n in a JSON string into a line break, so
# backslashes are doubled to survive that.
oneline() {
  printf '%s' "$*" \
    | tr '\n\r\t' '   ' \
    | sed -e 's/\\/\\\\/g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//'
}

# Parse an ISO-8601 timestamp into seconds since the epoch, coping with the
# busybox date found in some base images.
to_epoch() {
  local timestamp=$1
  if date --help 2>&1 | grep -qi busybox; then
    date -D %Y-%m-%dT%H:%M:%S --date="$timestamp" +%s 2>/dev/null
  else
    date --date="$timestamp" +%s 2>/dev/null
  fi
}

# Read the server identity configure-openvpn.sh recorded in the config.
read_config_metadata() {
  if [[ -z "$CONFIG" || ! -f "$CONFIG" ]]; then
    fatal_error "PIA: no OpenVPN config found at '${CONFIG:-<unset>}', cannot tell which server to ask for a port"
  fi

  # OpenVPN runs --route-up scripts with a scrubbed environment, so everything
  # here arrives through /etc/transmission/environment-variables.sh, which
  # persistEnvironment.py fills from an allowlist. CONFIG is on that list;
  # VPN_PROVIDER_HOME is not, so take the provider directory from the config
  # we were handed rather than trusting VPN_PROVIDER_HOME to be set.
  provider_home=$(dirname "$CONFIG")

  pf_cn=$(sed -n 's/^; pia_cn \(.*\)$/\1/p' "$CONFIG" | head -1)
  pf_region=$(sed -n 's/^; pia_region \(.*\)$/\1/p' "$CONFIG" | head -1)
  pf_region="${pf_region:-<unknown>}"

  log "PIA: port forwarding for region '$pf_region'${pf_cn:+ (server $pf_cn)}"
}

# The PIA_* settings are not on persistEnvironment.py's allowlist either, so
# configure-openvpn.sh writes them next to the configs for us to pick up.
load_provider_settings() {
  local settings="${provider_home}/pia-nextgen.env"

  if [[ -r "$settings" ]]; then
    # shellcheck source=/dev/null
    . "$settings"
  fi

  PIA_PF_INSECURE="${PIA_PF_INSECURE:-false}"
  PIA_PF_REUSE="${PIA_PF_REUSE:-true}"
  PF_STATE_FILE="${PIA_PF_STATE_FILE:-/config/pia-nextgen-portforward.json}"
}

##
# Locating the port forwarding API
##

# The gateway comes from the default route rather than the first tun line we
# happen to see, which can be our own tunnel address or a pushed host route.
find_gateway() {
  pf_gateway=$(ip route | awk '/^(default|0\.0\.0\.0\/1)[[:space:]]/ && /dev (tun|tap)/ { print $3; exit }')

  if [[ -z "$pf_gateway" ]]; then
    fatal_error "PIA: no VPN gateway found on a tun/tap default route, is the tunnel up?"
  fi
  log "PIA: VPN gateway is $pf_gateway"
}

# Decide how API calls authenticate the server, and fail early if we cannot.
setup_tls() {
  local cacert="${provider_home}/ca.rsa.4096.crt"

  if [[ "${PIA_PF_INSECURE,,}" == "true" ]]; then
    log "PIA: WARNING: PIA_PF_INSECURE is set, the port forwarding API certificate will not be verified"
    pf_curl_tls=(--insecure)
    return 0
  fi

  if [[ -z "$pf_cn" ]]; then
    fatal_error "PIA: $CONFIG has no '; pia_cn' line, so the port forwarding API certificate cannot be verified. Configs generated by this provider always carry one. If you supplied your own config, regenerate it or set PIA_PF_INSECURE=true to connect without verifying."
  fi
  if [[ ! -f "$cacert" ]]; then
    fatal_error "PIA: $cacert is missing, so the port forwarding API certificate cannot be verified. Set PIA_PF_INSECURE=true to connect without verifying."
  fi

  pf_curl_tls=(--cacert "$cacert")
}

# The API is not always on the gateway. PIA also serves it from x.y.128.1 and,
# on newer servers, x.y.0.1, so probe each in turn and keep the first that
# answers. This mirrors what gluetun's findAPIIP does.
find_api_host() {
  local candidate second_octet rest

  rest=${pf_gateway#*.}
  second_octet=${rest%%.*}

  for candidate in $(printf '%s\n' \
      "$pf_gateway" \
      "${pf_gateway%%.*}.${second_octet}.128.1" \
      "${pf_gateway%%.*}.${second_octet}.0.1" | awk '!seen[$0]++'); do

    # No --fail: any HTTP response proves something is listening and, when we
    # are verifying, that it presented the right certificate.
    if api_probe "$candidate"; then
      pf_api_ip="$candidate"
      if [[ "${PIA_PF_INSECURE,,}" == "true" ]]; then
        pf_api_host="$candidate"
      else
        pf_api_host="$pf_cn"
        pf_curl_tls+=(--connect-to "${pf_cn}::${candidate}:")
        log "PIA: certificate verified as $pf_cn"
      fi
      log "PIA: port forwarding API found at ${pf_api_ip}:${PF_API_PORT}"
      return 0
    fi
    log "PIA: no port forwarding API at ${candidate}:${PF_API_PORT}"
  done

  fatal_error "PIA: could not reach a port forwarding API from gateway $pf_gateway. The tunnel is up, but region '$pf_region' is not serving port forwards. Check that it still has port_forward=true in the server list at https://serverlist.piaservers.net/vpninfo/servers/v6 -- and note that some regions advertise port forwarding but do not actually serve it, so it is worth trying another region too."
}

api_probe() {
  local ip=$1

  if [[ "${PIA_PF_INSECURE,,}" == "true" ]]; then
    curl --insecure --silent --output /dev/null --connect-timeout 5 \
      "https://${ip}:${PF_API_PORT}/ping"
  else
    curl --silent --output /dev/null --connect-timeout 5 \
      "${pf_curl_tls[@]}" --connect-to "${pf_cn}::${ip}:" \
      "https://${pf_cn}:${PF_API_PORT}/ping"
  fi
}

# One place where every port forwarding API request is built.
api_call() {
  local endpoint=$1
  shift

  curl --get --silent --show-error \
    --max-time "$CURL_MAX_TIME" \
    --retry "$CURL_RETRIES" --retry-delay "$CURL_RETRY_DELAY" \
    "${pf_curl_tls[@]}" \
    "$@" \
    "https://${pf_api_host}:${PF_API_PORT}/${endpoint}"
}

##
# Reservation: token, signature, keepalive
##

get_token() {
  local username password response

  if [[ ! -r "$OPENVPN_CREDENTIALS" ]]; then
    fatal_error "PIA: cannot read $OPENVPN_CREDENTIALS"
  fi
  username=$(sed -n 1p "$OPENVPN_CREDENTIALS")
  password=$(sed -n 2p "$OPENVPN_CREDENTIALS")

  response=$(curl --silent --show-error --max-time "$CURL_MAX_TIME" \
    --location --request POST \
    --form "username=${username}" \
    --form "password=${password}" \
    "$PF_TOKEN_URL")

  if [[ -z "$response" ]]; then
    fatal_error "PIA: no response from $PF_TOKEN_URL, is the tunnel up?"
  fi

  # jq exits 0 on a missing field, so check the value rather than jq's status:
  # a rejected login otherwise yields the literal string "null" as the token.
  pf_token=$(jq -r '.token // empty' <<< "$response")
  if [[ -z "$pf_token" ]]; then
    fatal_error "PIA: could not get an account token, check the credentials in $OPENVPN_CREDENTIALS. Response: $(oneline "$response")"
  fi

  log "PIA: acquired an account token"
}

request_signature() {
  local response decoded expires_raw

  response=$(api_call getSignature --data-urlencode "token=${pf_token}")

  if [[ "$(jq -r '.status // empty' <<< "$response")" != "OK" ]]; then
    fatal_error "PIA: getSignature failed at ${pf_api_ip}:${PF_API_PORT} for region '$pf_region'. Some regions advertise port forwarding but do not actually serve it, so it is worth trying another region. Response: $(oneline "${response:-<empty>}")"
  fi

  pf_payload=$(jq -r '.payload // empty' <<< "$response")
  pf_signature=$(jq -r '.signature // empty' <<< "$response")
  if [[ -z "$pf_payload" || -z "$pf_signature" ]]; then
    fatal_error "PIA: getSignature returned no payload or signature. Response: $(oneline "$response")"
  fi

  decoded=$(base64 -d <<< "$pf_payload" 2>/dev/null)
  pf_port=$(jq -r '.port // empty' <<< "$decoded")
  expires_raw=$(jq -r '.expires_at // empty' <<< "$decoded")
  if [[ -z "$pf_port" || -z "$expires_raw" ]]; then
    fatal_error "PIA: could not read a port and expiry out of the signed payload. Payload: $(oneline "${decoded:-<undecodable>}")"
  fi

  pf_expires_at=$(to_epoch "$expires_raw")
  if [[ -z "$pf_expires_at" ]]; then
    fatal_error "PIA: could not parse the reservation expiry '$expires_raw'"
  fi

  log "PIA: reserved port $pf_port until $(date -d "@$pf_expires_at")"
  save_reservation
}

bind_port() {
  local response

  response=$(api_call bindPort \
    --data-urlencode "payload=${pf_payload}" \
    --data-urlencode "signature=${pf_signature}")

  if [[ "$(jq -r '.status // empty' <<< "$response")" != "OK" ]]; then
    log "PIA: bindPort failed at ${pf_api_ip}:${PF_API_PORT}. Response: $(oneline "${response:-<empty>}")"
    return 1
  fi

  return 0
}

##
# Caching the reservation across restarts
##

# PIA_PF_REUSE turns the cache off entirely: nothing is read and nothing is
# written, so each start asks PIA for a fresh port.
reuse_enabled() {
  [[ "${PIA_PF_REUSE,,}" == "true" ]]
}

save_reservation() {
  local dir

  if ! reuse_enabled; then
    return 0
  fi

  dir=$(dirname "$PF_STATE_FILE")

  if ! mkdir -p "$dir" 2>/dev/null; then
    log "PIA: cannot write to $dir, the port will not be kept across restarts"
    return 0
  fi

  if jq -n --arg payload "$pf_payload" \
          --arg signature "$pf_signature" \
          --arg port "$pf_port" \
          --arg expires_at "$pf_expires_at" \
          '{payload: $payload, signature: $signature, port: $port, expires_at: $expires_at}' \
       > "${PF_STATE_FILE}.tmp" 2>/dev/null && mv "${PF_STATE_FILE}.tmp" "$PF_STATE_FILE"; then
    chmod 600 "$PF_STATE_FILE" 2>/dev/null
    log "PIA: saved the reservation to $PF_STATE_FILE"
  else
    rm -f "${PF_STATE_FILE}.tmp"
    log "PIA: could not save the reservation to $PF_STATE_FILE, the port will not be kept across restarts"
  fi
}

# Reuse a cached reservation if there is one and it is not about to expire.
# The reservation is not tied to a server, so it stays valid across restarts
# and even across regions.
load_reservation() {
  local payload signature port expires_at now

  if ! reuse_enabled; then
    log "PIA: PIA_PF_REUSE is '$PIA_PF_REUSE', requesting a new port instead of reusing a cached one"
    return 1
  fi

  [[ -r "$PF_STATE_FILE" ]] || return 1

  payload=$(jq -r '.payload // empty' "$PF_STATE_FILE" 2>/dev/null)
  signature=$(jq -r '.signature // empty' "$PF_STATE_FILE" 2>/dev/null)
  port=$(jq -r '.port // empty' "$PF_STATE_FILE" 2>/dev/null)
  expires_at=$(jq -r '.expires_at // empty' "$PF_STATE_FILE" 2>/dev/null)

  if [[ -z "$payload" || -z "$signature" || -z "$port" || -z "$expires_at" ]]; then
    log "PIA: ignoring an unreadable reservation in $PF_STATE_FILE"
    return 1
  fi

  now=$(date +%s)
  if (( expires_at - now < PF_RENEW_MARGIN )); then
    log "PIA: the cached reservation has expired, requesting a new one"
    return 1
  fi

  pf_payload=$payload
  pf_signature=$signature
  pf_port=$port
  pf_expires_at=$expires_at

  log "PIA: reusing port $pf_port from $PF_STATE_FILE, valid until $(date -d "@$pf_expires_at")"
  return 0
}

# Get a reservation, from cache when possible, and bind it.
obtain_and_bind_port() {
  if load_reservation && bind_port; then
    return 0
  fi

  get_token
  request_signature

  if ! bind_port; then
    fatal_error "PIA: could not bind port $pf_port on ${pf_api_ip}:${PF_API_PORT} for region '$pf_region'."
  fi
}

##
# Transmission
##

transmission_rpc_host() {
  local rpc_url="$TRANSMISSION_RPC_URL"

  if [[ -z "$rpc_url" ]]; then
    rpc_url=$(jq -r '."rpc-url"' /etc/transmission/default-settings.json)
  fi

  # transmission-remote wants the URL without a trailing slash
  sed -E 's#/$##' <<< "http://localhost:${TRANSMISSION_RPC_PORT}${rpc_url}"
}

transmission_auth_args() {
  local settings="${TRANSMISSION_HOME}/settings.json"

  grep -q '"rpc-authentication-required":[[:space:]]*true' "$settings" 2>/dev/null || return 0

  if [[ ! -r "$TRANSMISSION_CREDENTIALS" ]]; then
    fatal_error "PIA: transmission requires authentication but $TRANSMISSION_CREDENTIALS is not readable"
  fi

  printf '%s' "--auth $(head -1 "$TRANSMISSION_CREDENTIALS"):$(tail -1 "$TRANSMISSION_CREDENTIALS")"
}

wait_for_transmission() {
  local host=$1 auth=$2

  log "PIA: waiting for transmission to become responsive"
  # shellcheck disable=SC2086
  until transmission-remote "$host" $auth --list >/dev/null 2>&1; do
    sleep 10
  done
  log "PIA: transmission is responsive"
}

apply_port_to_transmission() {
  local host auth current
  host=$(transmission_rpc_host)
  auth=$(transmission_auth_args)

  wait_for_transmission "$host" "$auth"

  # Transmission 3.x prints "Listenport:" and 4.x prints "Listen port:", so
  # match both rather than silently reading an empty port.
  # shellcheck disable=SC2086
  current=$(transmission-remote "$host" $auth --session-info 2>/dev/null \
    | awk -F': *' 'tolower($1) ~ /listen ?port$/ { print $2; exit }' \
    | grep -oE '[0-9]+')

  if [[ "$current" == "$pf_port" ]]; then
    log "PIA: transmission is already listening on $pf_port"
    return 0
  fi

  if [[ "${ENABLE_UFW,,}" == "true" ]]; then
    log "PIA: updating UFW rules, denying $current and allowing $pf_port"
    [[ -n "$current" ]] && ufw deny "$current"
    ufw allow "$pf_port"
  fi

  log "PIA: setting the transmission peer port to $pf_port (was ${current:-unknown})"
  # shellcheck disable=SC2086
  transmission-remote "$host" $auth --port "$pf_port"

  sleep 10
  log "PIA: Forcing transmission to test the new port $pf_port"
  # shellcheck disable=SC2086
  transmission-remote "$host" $auth --port-test
}

##
# Main
##

main() {
  require_tools
  read_config_metadata
  load_provider_settings
  find_gateway
  setup_tls
  find_api_host

  obtain_and_bind_port
  apply_port_to_transmission

  log "PIA: forwarding port $pf_port, refreshing every $((PF_BIND_INTERVAL / 60)) minutes"

  local previous_port
  while true; do
    # Interruptible sleep, so the container stops promptly on a signal.
    sleep "$PF_BIND_INTERVAL" &
    wait $!

    if (( pf_expires_at - $(date +%s) < PF_RENEW_MARGIN )); then
      log "PIA: the reservation is about to expire, requesting a new one"
      previous_port=$pf_port
      get_token
      request_signature
      if ! bind_port; then
        fatal_error "PIA: could not bind the renewed port $pf_port on ${pf_api_ip}:${PF_API_PORT}."
      fi
      if [[ "$pf_port" != "$previous_port" ]]; then
        apply_port_to_transmission
      fi
      continue
    fi

    if ! bind_port; then
      fatal_error "PIA: lost the port forward for $pf_port on ${pf_api_ip}:${PF_API_PORT}. The reservation is gone, so the container is stopping rather than leaving transmission listening on a port that is no longer forwarded."
    fi
    log "PIA: refreshed port $pf_port"
  done
}

main "$@"
