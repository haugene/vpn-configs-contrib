#!/bin/bash
#
# get config name based on api recommendation + ENV Vars (NORDVPN_COUNTRY, NORDVPN_PROTOCOL, NORDVPN_CATEGORY)
#
# NORDVPN_COUNTRY: code or name https://api.nordvpn.com/v1/servers/countries
# NORDVPN_PROTOCOL: tcp or upd, tcp if none or unknown. Will request api with openvpn_<NORDVPN_PROTOCOL>. many are available but not used. curl -s https://api.nordvpn.com/v1/technologies | jq .[].identifier
# NORDVPN_CATEGORY: curl -s https://api.nordvpn.com/v1/servers/groups | jq .[].identifier
#
# 2021/09
#

#Changes
# 2021/09/15: check ENV values if still supported

set -e
#Variables
TIME_FORMAT=$(date "+%Y-%m-%d %H:%M:%S")
nordvpn_api="https://api.nordvpn.com"
nordvpn_dl=downloads.nordcdn.com
nordvpn_cdn="https://${nordvpn_dl}/configs/files"
nordvpn_doc="https://haugene.github.io/docker-transmission-openvpn/provider-specific/#nordvpn"
possible_protocol="tcp, udp"

#Functions
log() {
  printf "${TIME_FORMAT} %b\n" "$*" >/dev/stderr
}

fatal_error() {
  printf "${TIME_FORMAT} \e[41mERROR:\033[0m %b\n" "$*" >&2
  exit 1
}

# check for utils
script_needs() {
  command -v $1 >/dev/null 2>&1 || fatal_error "This script requires $1 but it's not installed. Please install it and run again."
}

script_init() {
  log "Checking curl installation"
  script_needs curl
}

country_filter() { # curl -s "https://api.nordvpn.com/v1/servers/countries" | jq --raw-output '.[] | [.code, .name] | @tsv'
  local nordvpn_api=$1 country=(${NORDVPN_COUNTRY//[;,]/ })
  if [[ ${#country[@]} -ge 1 ]]; then
    country=${country[0]//_/ }
    local country_id=$(curl -s "${nordvpn_api}/v1/servers/countries" | jq --raw-output ".[] |
                          select( (.name|test(\"^${country}$\";\"i\")) or
                                  (.code|test(\"^${country}$\";\"i\")) ) |
                          .id" | head -n 1)
    if [[ -n ${country_id} ]]; then
      log "Searching for country : ${country} (${country_id})"
      echo "filters\[country_id\]=${country_id}&"
    else
      log "Warning, no country found for NORDVPN_COUNTRY=${NORDVPN_COUNTRY}. Ignoring this parameter. Possible values are:${possible_country_codes[*]} or ${possible_country_names[*]}. Please check ${nordvpn_doc}"
    fi
  fi
}
group_filter() { # curl -s "https://api.nordvpn.com/v1/servers/groups" | jq --raw-output '.[] | [.identifier, .title] | @tsv'
  local nordvpn_api=$1 category=(${NORDVPN_CATEGORY//[;,]/ })
  if [[ ${#category[@]} -ge 1 ]]; then
    #category=${category[0]//_/ }
    local identifier=$(curl -s "${nordvpn_api}/v1/servers/groups" | jq --raw-output ".[] |
                          select( ( .identifier|test(\"${category}\";\"i\")) or
                                  ( .title| test(\"${category}\";\"i\")) ) |
                          .identifier" | head -n 1)
    if [[ -n ${identifier} ]]; then
      log "Searching for group: ${identifier}"
      echo "filters\[servers_groups\]\[identifier\]=${identifier}&"
    else
      log "No group found for NORDVPN_CATEGORY=${NORDVPN_CATEGORY}. ignoring this parameters. Please check ${nordvpn_doc}"
    fi
  fi
}

technology_filter() { # curl -s "https://api.nordvpn.com/v1/technologies" | jq --raw-output '.[] | [.identifier, .name ] | @tsv' | grep openvpn
  local identifier
  if [[ ${NORDVPN_PROTOCOL,,} =~ .*udp.* ]]; then
    identifier="openvpn_udp"
  elif [[ ${NORDVPN_PROTOCOL,,} =~ .*tcp.* ]]; then
    identifier="openvpn_tcp"
  fi
  if [[ -n ${identifier} ]]; then
    log "Searching for technology: ${identifier}"
    echo "filters\[servers_technologies\]\[identifier\]=${identifier}&"
  else
    log "No protocol found for NORDVPN_PROTOCOL=${NORDVPN_PROTOCOL}, expecting tcp or udp. set default to tcp. Please read ${nordvpn_doc}"
    echo "filters\[servers_technologies\]\[identifier\]=openvpn_tcp&"
    export NORDVPN_PROTOCOL=tcp
  fi
}

select_hostname() { #TODO return multiples
  local filters hostname

  log "Selecting the best server..."
  if [[ "$1" != "-d" ]]; then
    filters+="$(country_filter ${nordvpn_api})"
  fi
  filters+="$(group_filter ${nordvpn_api})"
  filters+="$(technology_filter)"

  hostname=$(curl -s "${nordvpn_api}/v1/servers/recommendations?${filters}limit=1" | jq --raw-output ".[].hostname")
  if [[ -z ${hostname} ]]; then
    log "Unable to find a server with the specified parameters, using any recommended server"
    hostname=$(curl -s "${nordvpn_api}/v1/servers/recommendations?limit=1" | jq --raw-output ".[].hostname")
  fi

  log "Best server : ${hostname}"
  echo ${hostname}
}
download_hostname() {
  #udp ==> https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/nl601.nordvpn.com.udp.ovpn
  #tcp ==> https://downloads.nordcdn.com/configs/files/ovpn_tcp/servers/nl542.nordvpn.com.tcp.ovpn
  local nordvpn_cdn=${nordvpn_cdn}
  #which protocol tcp or udp
  if [[ ${NORDVPN_PROTOCOL,,} == udp ]]; then
    nordvpn_cdn="${nordvpn_cdn}/ovpn_udp/servers/"
  elif [[ ${NORDVPN_PROTOCOL,,} == tcp ]]; then
    nordvpn_cdn="${nordvpn_cdn}/ovpn_tcp/servers/"
  else
    # defaulting to tcp
    nordvpn_cdn="${nordvpn_cdn}/ovpn_tcp/servers/"
  fi

  # default or defined
  if [[ "-d" == "$1" ]]; then
    nordvpn_cdn=${nordvpn_cdn}${2}
    ovpnName=default.ovpn
  else
    nordvpn_cdn=${nordvpn_cdn}${1}
    ovpnName=${1}.ovpn
  fi

  # remote filename
  if [[ ${NORDVPN_PROTOCOL,,} == udp ]]; then
    nordvpn_cdn="${nordvpn_cdn}.udp.ovpn"
  elif [[ ${NORDVPN_PROTOCOL,,} == tcp ]]; then
    nordvpn_cdn="${nordvpn_cdn}.tcp.ovpn"
  else
    nordvpn_cdn="${nordvpn_cdn}.tcp.ovpn"
  fi

  log "Downloading config: ${ovpnName}"
  log "Downloading from: ${nordvpn_cdn}"
  curl -sSL ${nordvpn_cdn} -o "${ovpnName}"
}

checkDNS() {
  res=$(dig +short ${nordvpn_dl})
  if [ -z "${res:-\"\"}" ]; then
    log "DNS: ERROR, no dns resolution, dns server unavailable or network problem"
  else
    log "DNS: resolution ok"
  fi
  ping -c2 ${nordvpn_dl} 2>&1 >/dev/null
  ret=$?
  if [ $ret -eq 0 ]; then
    log "PING: ok, configurations download site reachable"
  else
    log "PING: ERROR: cannot ping ${nordvpn_cdn}, network or internet unavailable. Cannot download NORDVPN configuration files"
  fi
  return $ret
}

# Main
# If the script is called from elsewhere
cd "${0%/*}"
script_init
checkDNS

possible_categories=($(curl -s ${nordvpn_api}/v1/servers/groups | jq -r .[].identifier | tr '\n' ', '))
possible_country_codes=($(curl -s ${nordvpn_api}/v1/servers/countries | jq -r .[].code | tr '\n' ', '))
possible_country_names=($(curl -s ${nordvpn_api}/v1/servers/countries | jq -r .[].name | tr '\n' ', '))

log "Removing existing configs"
find . ! -name '*.sh' -type f -delete

if [[ ! -z $OPENVPN_CONFIG ]] && [[ ! -z $NORDVPN_COUNTRY ]]; then
  default="$(select_hostname)"
else
  default="$(select_hostname -d)"
fi

download_hostname -d ${default}

if [[ ${1} == "--get-recommended" ]] || [[ ${1} == "-r" ]]; then
  selected="default"
elif [[ ${1} == "--openvpn-config" ]] || [[ ${1} == "-o" ]]; then
  log "Using OpenVPN CONFIG :: ${OPENVPN_CONFIG,,}"
  download_hostname ${OPENVPN_CONFIG,,}
elif [[ ! -z $NORDVPN_COUNTRY ]]; then
  selected="$(select_hostname)"
  download_hostname ${selected}
else
  selected="default"
fi

if [[ ! -z $selected ]]; then
  echo ${selected}
fi

cd "${0%/*}"