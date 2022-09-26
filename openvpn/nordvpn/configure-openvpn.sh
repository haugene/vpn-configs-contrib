#!/bin/bash
#
# get config name based on api recommendation + ENV Vars (NORDVPN_COUNTRY, NORDVPN_PROTOCOL, NORDVPN_CATEGORY)
#
# 2021/09
#
#
# NORDVPN_COUNTRY: code or name
# curl -s "https://api.nordvpn.com/v1/servers/countries" | jq --raw-output '.[] | [.code, .name] | @tsv'
# NORDVPN_PROTOCOL: tcp or upd, tcp if none or unknown. Many technologies are not used as only openvpn_udp and openvpn_tcp are tested.
# Will request api with openvpn_<NORDVPN_PROTOCOL>.
# curl -s "https://api.nordvpn.com/v1/technologies" | jq --raw-output '.[] | [.identifier, .name ] | @tsv' | grep openvpn
# NORDVPN_CATEGORY: default p2p. not all countries have all combination of NORDVPN_PROTOCOL(technologies) and NORDVPN_CATEGORY(groups),
# hence many queries to the api may return no recommended servers.
# curl -s https://api.nordvpn.com/v1/servers/groups | jq .[].identifier
#
#Changes
# 2021/09/15: check ENV values if still supported
# 2021/09/22: store json results, merged configure-openvpn + updateConfigs.sh: OPENVPN_CONFIG is confusing for users. (#1958)

set -e
[[ -f /etc/openvpn/utils.sh ]] && source /etc/openvpn/utils.sh || true

#Variables
TIME_FORMAT=$(date "+%Y-%m-%d %H:%M:%S")
nordvpn_api="https://api.nordvpn.com"
nordvpn_dl=downloads.nordcdn.com
nordvpn_cdn="https://${nordvpn_dl}/configs/files"
nordvpn_doc="https://haugene.github.io/docker-transmission-openvpn/provider-specific/#nordvpn"
possible_protocol="tcp, udp"
VPN_PROVIDER_HOME=${VPN_PROVIDER_HOME:-/etc/openvpn/nordvpn}

# Functions

# Normal run functions
log() {
  printf "${TIME_FORMAT} %b\n" "$*" >/dev/stderr
}

fatal_error() {
  printf "${TIME_FORMAT} \e[41mERROR:\033[0m %b\n" "$*" >&2
  exit 1
}

download_configs() {
  hostnames=( $(curl -s "${nordvpn_api}/v1/servers?limit=6000" | jq --raw-output ".[].hostname") )
  if [[ -z ${hostnames} ]]; then
    log "Warning, unable to find Nord VPN servers."
    echo ''
  else
    for hostname in "${hostnames[@]}"; do
      download_hostname "${hostname}"
    done
  fi
}

download_hostname() {
  #udp ==> https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/nl601.nordvpn.com.udp.ovpn
  [[ -z ${1} ]] && return || true

  # default or defined server name
  local nordvpn_cdn=${nordvpn_cdn}/ovpn_udp/servers/${1}.udp.ovpn
  ovpnName=${1}.ovpn

  log "Downloading config: ${ovpnName}"
  log "Downloading from: ${nordvpn_cdn}"

  # VPN_PROVIDER_HOME defined is openvpn/start.sh
  outfile="-o "${VPN_PROVIDER_HOME}/${ovpnName}
  curl -sSL ${nordvpn_cdn} ${outfile}
}

log "Removing existing configs in ${VPN_PROVIDER_HOME}"
find ${VPN_PROVIDER_HOME} -type f ! -name '*.sh' -delete

download_configs
