#! /bin/bash
#
# Generate one OpenVPN config per region from PIA's server list API.
#
# PIA runs two OpenVPN networks. The legacy one is reached through
# <region>.privacy.network, which is a mixed DNS pool: it also hands out hosts
# PIA classifies as "meta" and addresses that are not in the server list at all,
# so there is no way to tell which machine in a region you actually land on.
# The next-generation network is the one PIA's own manual-connections scripts
# use. Its server list names exactly which IP serves OpenVPN for each region,
# on udp/8080 or tcp/8443, with aes-256-cbc + sha256 against the rsa-4096 CA
# shipped next to this script.
#
# Configs are assembled the way manual-connections does it: take the template,
# which deliberately has no remote line, and append a remote for the server we
# picked. Nothing is downloaded from PIA except the server list itself.
#
# NOTE: start.sh *sources* this script, so it runs in start.sh's own shell with
# set -e active. That has two consequences worth keeping in mind when editing:
# "exit 1" aborts container startup (which is how we want to fail hard), and an
# unguarded non-zero exit status does the same by accident. Use explicit if
# blocks rather than "test && command". The work lives in a function so we do
# not leak variables back into start.sh.

source /etc/openvpn/utils.sh

# Flatten a value onto a single line before it goes into a message, so one log
# event stays one line. utils.sh logs with printf "%b", which would also turn a
# literal backslash-n in a response body into a line break, so backslashes are
# doubled to survive that.
pia_nextgen_oneline() {
    printf '%s' "$*" \
        | tr '\n\r\t' '   ' \
        | sed -e 's/\\/\\\\/g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//'
}

pia_nextgen_generate_configs() {
    local serverlist_url="https://serverlist.piaservers.net/vpninfo/servers/v6"
    local template="${VPN_PROVIDER_HOME}/strong.template"
    local protocol group port pf_only serverlist regions
    local id name ip cn config generated_count
    local -a ids=() aliases=()

    if [[ -z "$VPN_PROVIDER_HOME" ]]; then
        fatal_error "PIA next-gen: VPN_PROVIDER_HOME is not set, cannot generate configs"
    fi
    if [[ ! -f "$template" ]]; then
        fatal_error "PIA next-gen: config template $template is missing"
    fi
    if [[ ! -f "${VPN_PROVIDER_HOME}/ca.rsa.4096.crt" ]]; then
        # Not used by the tunnel (the CA is inline in the template) but
        # update-port.sh needs it to verify the port forwarding API.
        log "PIA next-gen: WARNING: ca.rsa.4096.crt is missing, port forwarding will not be able to verify TLS"
    fi

    # udp/8080 and tcp/8443 are what connect_to_openvpn_with_token.sh uses, and
    # match groups.ovpnudp/ovpntcp in the server list. The legacy ports (1197,
    # 1198) are not open on these servers.
    protocol="${PIA_NEXTGEN_PROTOCOL:-udp}"
    protocol="${protocol,,}"
    case "$protocol" in
        udp) group="ovpnudp"; port=8080 ;;
        tcp) group="ovpntcp"; port=8443 ;;
        *)   fatal_error "PIA next-gen: PIA_NEXTGEN_PROTOCOL must be udp or tcp, got '${PIA_NEXTGEN_PROTOCOL}'" ;;
    esac

    # PIA_PF mirrors get_region.sh: keep only regions PIA advertises as port
    # forwarding capable. Note that this is only what PIA advertises; a few of
    # those regions do not actually serve forwards.
    if [[ "${PIA_PF,,}" == "true" ]]; then
        pf_only=true
        log "PIA next-gen: PIA_PF is set, keeping only regions that advertise port forwarding"
    else
        pf_only=false
    fi

    log "PIA next-gen: fetching server list from $serverlist_url"
    # The body is JSON on the first line followed by a signature, hence head -1.
    serverlist=$(curl --silent --show-error --fail --max-time 30 \
        --retry 3 --retry-delay 5 "$serverlist_url" | head -1)

    if [[ -z "$serverlist" ]]; then
        fatal_error "PIA next-gen: got an empty server list from $serverlist_url. Check that the container has network access before the tunnel comes up."
    fi
    if ! jq -e . >/dev/null 2>&1 <<< "$serverlist"; then
        fatal_error "PIA next-gen: could not parse the server list from $serverlist_url as JSON. First 200 bytes: $(pia_nextgen_oneline "${serverlist:0:200}")"
    fi

    # One jq pass for the whole list: region id, the region name normalised to
    # the filenames PIA uses in its own config bundle, and the first listed
    # OpenVPN server for the protocol we want.
    regions=$(jq -r --arg group "$group" --argjson pf_only "$pf_only" '
        .regions[]
        | select($pf_only == false or .port_forward == true)
        | select(.offline != true)
        | select((.servers[$group] // []) | length > 0)
        | [ .id,
            (.name | ascii_downcase | gsub(" "; "_")),
            .servers[$group][0].ip,
            .servers[$group][0].cn ]
        | @tsv
    ' <<< "$serverlist")

    if [[ -z "$regions" ]]; then
        if [[ "$pf_only" == true ]]; then
            fatal_error "PIA next-gen: no regions in the server list advertise port forwarding over $protocol. Unset PIA_PF to use every region."
        fi
        fatal_error "PIA next-gen: no regions in the server list offer OpenVPN over $protocol."
    fi

    # Drop configs generated by a previous run. The server list rotates, so
    # yesterday's IPs are not worth keeping. The template is deliberately not
    # named *.ovpn: start.sh lists "$VPN_PROVIDER_HOME"/*.ovpn as the options
    # for OPENVPN_CONFIG, and provider_test.py globs the same pattern, so a
    # template with no remote line must not look like a selectable config.
    find "$VPN_PROVIDER_HOME" -maxdepth 1 \( -type f -o -type l \) \
        -name '*.ovpn' -delete

    while IFS=$'\t' read -r id name ip cn; do
        if [[ -z "$id" || -z "$ip" ]]; then
            continue
        fi

        config="${VPN_PROVIDER_HOME}/${id}.ovpn"
        cat "$template" > "$config"
        {
            echo "remote $ip $port $protocol"
            # update-port.sh reads pia_cn back out to verify the port forwarding
            # API's certificate. "; " comments are an established idiom here;
            # modify-openvpn-config.sh appends "; status <...>" the same way.
            echo "; pia_cn $cn"
            echo "; pia_region $id"
        } >> "$config"

        ids+=("$id")
        # PIA's own bundle names its files after the region name, not the id.
        # Emit those as symlinks so anyone moving over from the "pia" provider
        # can keep their existing OPENVPN_CONFIG value.
        if [[ -n "$name" && "$name" != "$id" ]]; then
            aliases+=("$name" "$id")
        fi
    done <<< "$regions"

    generated_count=${#ids[@]}
    if [[ $generated_count -eq 0 ]]; then
        fatal_error "PIA next-gen: the server list produced no usable configs."
    fi

    # Second pass, so an alias can never overwrite a region's own config: by now
    # every id config exists, and ln is skipped if anything is already there.
    local i alias_name alias_target
    for (( i = 0; i < ${#aliases[@]}; i += 2 )); do
        alias_name="${aliases[i]}"
        alias_target="${aliases[i+1]}"
        if [[ ! -e "${VPN_PROVIDER_HOME}/${alias_name}.ovpn" ]]; then
            ln -sf "${alias_target}.ovpn" "${VPN_PROVIDER_HOME}/${alias_name}.ovpn"
        fi
    done

    # start.sh's persistEnvironment.py carries only an allowlist of variables
    # through to update-port.sh, and the PIA_* settings are not on it. OpenVPN
    # also scrubs the environment for its --route-up scripts, so hand them over
    # in a file beside the configs instead. Deliberately not named *.ovpn.
    {
        echo "# Written by configure-openvpn.sh on each container start."
        echo "# update-port.sh reads this because start.sh does not persist"
        echo "# these variables into the environment it runs under."
        printf 'PIA_PF_INSECURE=%q\n' "${PIA_PF_INSECURE:-false}"
        printf 'PIA_PF_REUSE=%q\n' "${PIA_PF_REUSE:-true}"
        if [[ -n "${PIA_PF_STATE_FILE:-}" ]]; then
            printf 'PIA_PF_STATE_FILE=%q\n' "$PIA_PF_STATE_FILE"
        fi
    } > "${VPN_PROVIDER_HOME}/pia-nextgen.env"

    log "PIA next-gen: generated $generated_count configs for $protocol/$port"

    # Select a random server as default.ovpn
    ln -sf "${ids[RANDOM % generated_count]}.ovpn" "${VPN_PROVIDER_HOME}/default.ovpn"
}

pia_nextgen_generate_configs
