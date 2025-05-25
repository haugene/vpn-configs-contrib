#!/usr/bin/env bash

sleep 60

# Disabled exiting on errors to allow the script to keep running even if commands fail
set +e
set +u
set +o pipefail

# shellcheck source=/dev/null
. /etc/transmission/environment-variables.sh

TRANSMISSION_PASSWD_FILE=/config/transmission-credentials.txt

transmission_username=$(head -1 ${TRANSMISSION_PASSWD_FILE})
transmission_passwd=$(tail -1 ${TRANSMISSION_PASSWD_FILE})
transmission_settings_file=${TRANSMISSION_HOME}/settings.json

debug=false

echo_debug() {
    if [ "$debug" = true ]; then
        echo "[DEBUG] $*"
    fi
}

function box_out() {
    local s="$*"
    printf "\033[36m╭─%s─╮\n\033[36m│ \033[34m%s\033[36m │\n\033[36m╰─%s─╯\033[0;39m\n" "${s//?/─}" "$s" "${s//?/─}"
}

open_port() {
    timeout 5 natpmpc -a 1 0 udp 60 > /dev/null 2>&1 && timeout 5 natpmpc -a 1 0 tcp 60
}

remote() {
    if test -n "$myauth"; then
        timeout 5 "$tr_cmd" "$TRANSMISSION_RPC_PORT" --auth "$myauth" --json "$@"
    else
        timeout 5 "$tr_cmd" "$TRANSMISSION_RPC_PORT" --json "$@"
    fi
}

bind_trans() {
    # Ensure Transmission is responsive
    if test "$(remote --list | jq -r .result)" != "success"; then
        return 1
    fi

    # Check if port is already bound to Transmission
    if test "$pf_port" -eq "$(remote --session-info | jq -r '.arguments["peer-port"]' || echo 0)"; then
        return 0
    fi

    # Bind port to Transmission
    if test "$(remote --port "$pf_port" | jq -r .result)" != "success"; then
        return 1
    fi
    sleep 1

    # Verify that port was bound to Transmission
    if test "$pf_port" -eq "$(remote --session-info | jq -r '.arguments["peer-port"]' || echo 0)"; then
        return 0
    fi

    box_out "Command to change port from $last_port to $pf_port returned success but actually failed!"
    return 1
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

tr_cmd=$(command -v transmission-remote)
if [[ -z "$tr_cmd" ]]; then
    echo "Error: transmission-remote not found in PATH"
    exit 1
fi

if test "$(jq -r '.["rpc-authentication-required"]' "$transmission_settings_file")" == "true"; then
    myauth="$transmission_username:$transmission_passwd"
else
    myauth=""
fi

box_out "ProtonVPN Port Forwarding"
last_port="unset"

while true; do
    pf_port="$(open_port | sed -nr '1,//s/Mapped public port ([0-9]{4,5}) protocol.*/\1/p')"
    echo_debug "Current detected port: $pf_port"
    if [[ "$pf_port" =~ ^[0-9]+$ ]] && test "$pf_port" -gt 1024; then
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
