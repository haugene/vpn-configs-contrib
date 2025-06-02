#!/usr/bin/env bash

sleep 60
set -euo pipefail

# shellcheck source=/dev/null
. /etc/transmission/environment-variables.sh

TRANSMISSION_PASSWD_FILE=/config/transmission-credentials.txt
transmission_username=$(head -1 "${TRANSMISSION_PASSWD_FILE}")
transmission_passwd=$(tail -1 "${TRANSMISSION_PASSWD_FILE}")
transmission_settings_file=${TRANSMISSION_HOME}/settings.json

box_out() {
    local s="$*"
    printf "\033[36m╭─%s─╮\n\033[36m│ \033[34m%s\033[36m │\n\033[36m╰─%s─╯\033[0;39m\n" "${s//?/─}" "$s" "${s//?/─}"
}

open_port() {
    timeout 5 natpmpc -a 1 0 udp 60 > /dev/null 2>&1 && timeout 5 natpmpc -a 1 0 tcp 60
}

remote() {
    if [[ -n "$myauth" ]]; then
        timeout 5 "$tr_cmd" "$TRANSMISSION_RPC_PORT" --auth "$myauth" --json "$@"
    else
        timeout 5 "$tr_cmd" "$TRANSMISSION_RPC_PORT" --json "$@"
    fi
}

bind_trans() {
    # Ensure Transmission is responsive
    if [[ "$(remote --list | jq -r .result)" != "success" ]]; then
        return 1
    fi

    # Set last_port if unset
    if [[ "$last_port" == "unset" ]]; then
        last_port="$(remote --session-info | jq -r '.arguments["peer-port"]' || echo 0)"
        if ! [[ "$last_port" =~ ^[0-9]+$ && "$last_port" -gt 1024 ]]; then
            last_port="unset"
        fi
    fi

    # Check if port is already bound to Transmission
    if [[ "$new_port" -eq "$(remote --session-info | jq -r '.arguments["peer-port"]' || echo 0)" ]]; then
        return 0
    fi

    # Bind port to Transmission
    if [[ "$(remote --port "$new_port" | jq -r .result)" != "success" ]]; then
        return 1
    fi

    # Verify that port was bound to Transmission
    sleep 1
    if [[ "$new_port" -eq "$(remote --session-info | jq -r '.arguments["peer-port"]' || echo 0)" ]]; then
        return 0
    fi
    box_out "Command to change port to $new_port returned success but actually failed!"
    return 1
}

set_firewall() {
    if [[ "$ENABLE_UFW" != "true" ]]; then
        return 0
    fi

    # Deny old port
    if [[ "$last_port" =~ ^[0-9]+$ && "$last_port" -gt 1024 && "$current_port" != "$last_port" ]]; then
        if timeout 5 ufw status | grep -qw "$last_port"; then
            echo "Denying $last_port through the firewall"
            if ! timeout 5 ufw deny "$last_port"; then
                echo "Failed while denying port $last_port"
            fi
        fi
    fi

    # Allow new port
    if [[ "$current_port" =~ ^[0-9]+$ && "$current_port" -gt 1024 ]]; then
        if ! (timeout 5 ufw status | grep -qw "$current_port"); then
            echo "Allowing $current_port through the firewall"
            if ! timeout 5 ufw allow "$current_port"; then
                echo "Failed while allowing port $current_port"
            fi
        fi
    fi
}

if ! command -v jq > /dev/null 2>&1; then
    echo "jq is not installed! jq is required to configure ProtonVPN port forwarding."
    echo "port forwarding for ProtonVPN has not been configured."
    exit 1
fi

if ! command -v natpmpc > /dev/null 2>&1; then
    echo "natpmpc is not installed! natpmpc is required to configure ProtonVPN port forwarding."
    echo "port forwarding for ProtonVPN has not been configured."
    exit 1
fi

tr_cmd=$(command -v transmission-remote)
if [[ -z "$tr_cmd" ]]; then
    echo "Error: transmission-remote not found in PATH"
    exit 1
fi

if [[ "$(jq -r '.["rpc-authentication-required"]' "$transmission_settings_file")" == "true" ]]; then
    myauth="$transmission_username:$transmission_passwd"
else
    myauth=""
fi

box_out "ProtonVPN Port Forwarding"
last_port="unset"
current_port="unset"
double_check="false"

# Disable exiting on errors to allow the script to keep running even if commands fail
set +e

while true; do
    new_port="$(open_port | sed -nr '1,//s/Mapped public port ([0-9]{4,5}) protocol.*/\1/p')"
    if [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -gt 1024 ]]; then
        if [[ "$new_port" != "$current_port" ]]; then
            if [[ "$double_check" != "true" ]]; then
                if bind_trans; then
                    if [[ "$current_port" != "unset" ]]; then
                        last_port="$current_port"
                    fi
                    current_port="$new_port"
                    double_check="true"
                    box_out "The forwarded port is: $current_port"
                else
                    box_out "Attempt to change port to $new_port failed!"
                fi
            else
                double_check="false"
            fi
        else
            double_check="true"
        fi
        set_firewall
    else
        box_out "No valid port returned from natpmpc"
    fi
    sleep 45
done
