#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
. /etc/transmission/environment-variables.sh

TRANSMISSION_PASSWD_FILE=/config/transmission-credentials.txt

transmission_username=$(head -1 ${TRANSMISSION_PASSWD_FILE})
transmission_passwd=$(tail -1 ${TRANSMISSION_PASSWD_FILE})
transmission_settings_file=${TRANSMISSION_HOME}/settings.json

function box_out() {
    local s="$*"
    printf "\033[36m╭─%s─╮\n\033[36m│ \033[34m%s\033[36m │\n\033[36m╰─%s─╯\033[0;39m\n" "${s//?/─}" "$s" "${s//?/─}"
}

open_port() {
    natpmpc -a 1 0 udp 60 && natpmpc -a 1 0 tcp 60
}

remote() {
    if test -n "$myauth"; then
        transmission-remote "$TRANSMISSION_RPC_PORT" --auth "$myauth" --json "$@"
    else
        transmission-remote "$TRANSMISSION_RPC_PORT" --json "$@"
    fi
}

bind_trans() {
    local new_port=$pf_port

    # Check if transmission remote is set up with authentication
    if test "$(jq -r '.["rpc-authentication-required"]' "$transmission_settings_file")" == "true"; then
        myauth="$transmission_username:$transmission_passwd"
    else
        myauth=""
    fi

    # Ensure transmission is responsive
    for attempt in {1..3}; do
        if test "$(remote --list | jq -r .result)" == "success"; then
            break
        fi
        sleep 5
        if [ "$attempt" -eq 3 ]; then
            return 1
        fi
    done

    # Bind port to Transmission
    transmission_peer_port=$(remote --session-info | jq -r '.arguments["peer-port"]')
    if test "$new_port" -ne "$transmission_peer_port"; then
        for attempt in {1..3}; do
            if test "$(remote --port "$new_port" | jq -r .result)" == "success"; then
                return 0
            fi
            sleep 5
        done
        return 1
    fi

    return 0
}

if ! which jq; then
    echo "jq is not installed! jq is required to configure ProtonVPN port forwarding."
    echo "port forwarding for ProtonVPN has not been configured."
    exit 1
fi

if ! which natpmpc; then
    echo "natpmpc is not installed! natpmpc is required to configure ProtonVPN port forwarding."
    echo "port forwarding for ProtonVPN has not been configured."
    exit 1
fi

sleep 60
box_out "ProtonVPN Port Forwarding"
last_port=""

while true; do
    pf_port="$(open_port | sed -nr '1,//s/Mapped public port ([0-9]{4,5}) protocol.*/\1/p')"
    if test "$pf_port" -gt 1024; then
        if [[ "$pf_port" != "$last_port" ]]; then
            if bind_trans; then
                last_port="$pf_port"
                box_out "The forwarded port is: $pf_port"
            else
                box_out "Attempt to change port from $last_port to $pf_port failed!"
            fi
        fi
    else
        box_out "No valid port returned from natpmpc"
    fi
    sleep 45
done
