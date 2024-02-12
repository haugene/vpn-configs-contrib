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
    natpmpc -a 1 0 udp 60 -g 10.2.0.1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1
}

remote() {
    if test -n "$myauth"; then
        transmission-remote "$TRANSMISSION_RPC_PORT" --auth "$myauth" --json "$@"
    else
        transmission-remote "$TRANSMISSION_RPC_PORT" --json "$@"
    fi
}

# this function borrowed from openvpn/pia/update-port.sh
bind_trans() {
    new_port=$pf_port
    local transmission_port_check_max_attempts=50
    local transmission_port_check_attempts=0
    local transmission_port_check_interval=10
    #
    # Now, set port in Transmission
    #

    # Check if transmission remote is set up with authentication
    if test "$(jq -r '.["rpc-authentication-required"]' "$transmission_settings_file")" == "true"; then
        echo "transmission auth required"
        myauth="$transmission_username:$transmission_passwd"
    else
        echo "transmission auth not required"
        myauth=""
    fi

    # make sure transmission is running and accepting requests
    echo "waiting for transmission to become responsive"
    until test "$(remote --list | jq -r .result)" == "success"; do sleep 10; done
    echo "transmission became responsive"

    # get current listening port
    transmission_peer_port=$(remote --session-info | jq -r '.arguments["peer-port"]')
    if test "$new_port" -ne "$transmission_peer_port"; then
        if test "$ENABLE_UFW" == "true"; then
            echo "Update UFW rules before changing port in Transmission"

            echo "denying access to $transmission_peer_port"
            ufw deny "$transmission_peer_port"

            echo "allowing $new_port through the firewall"
            ufw allow "$new_port"
        fi

        echo "setting transmission port to $new_port"
        until test "$(remote --port "$new_port" | jq -r .result)" == "success"; do sleep 5; done

        echo "Waiting for port..."
        until test "$(remote --port-test | jq -r '.arguments["port-is-open"]')" == "true"; do
            if test $transmission_port_check_attempts -ge $transmission_port_check_max_attempts; then
                echo "Port check attempts exceeded, giving up..."
                return 1
            else
                printf "Attempt %d of %d. Port is not open yet, waiting %d seconds...\n" $(( transmission_port_check_attempts + 1 )) $transmission_port_check_max_attempts $transmission_port_check_interval
                ((transmission_port_check_attempts++))
                sleep $transmission_port_check_interval
            fi
        done
        echo "Port is open!"
    else
        echo "No action needed, port hasn't changed"
    fi
}

if ! which jq; then
    echo "jq is not installed."
    exit 1
fi

if ! which natpmpc; then
    echo "natpmpc is not installed. natpmpc is required to configure ProtonVPN port forwarding."
    echo "port forwarding for ProtonVPN has not been configured."
    exit 1
fi

box_out "ProtonVPN Port Forwarding"

while true; do
    date
    pf_port="$(open_port | sed -nr '1,//s/Mapped public port ([0-9]{4,5}) protocol.*/\1/p')"
    if test "$pf_port" -gt 1024; then
        if bind_trans; then
            box_out "The Forwarded Port is: $pf_port"
        else
            box_out "The Forwarded Port is: Unavailable"
        fi
    else
        box_out "No Port Retuned from natpmpc"
    fi

    sleep 35
done
