#!/bin/bash
#
#
. /etc/transmission/environment-variables.sh

TRANSMISSION_PASSWD_FILE=/config/transmission-credentials.txt

transmission_username=$(head -1 ${TRANSMISSION_PASSWD_FILE})
transmission_passwd=$(tail -1 ${TRANSMISSION_PASSWD_FILE})
transmission_settings_file=${TRANSMISSION_HOME}/settings.json

echo "-------------------------"
echo "ProtonVPN Port Forwarding"
echo "-------------------------"

# this function borrowed verbatim from openvpn/pia/update-port.sh
bind_trans() {
	new_port=$pf_port
	#
	# Now, set port in Transmission
	#

	# Check if transmission remote is set up with authentication
	auth_enabled=$(grep 'rpc-authentication-required\"' "$transmission_settings_file" |
		grep -oE 'true|false')

	if [[ "true" = "$auth_enabled" ]]; then
		echo "transmission auth required"
		myauth="--auth $transmission_username:$transmission_passwd"
	else
		echo "transmission auth not required"
		myauth=""
	fi

	# make sure transmission is running and accepting requests
	echo "waiting for transmission to become responsive"
	until torrent_list="$(transmission-remote $TRANSMISSION_RPC_PORT $myauth -l)"; do sleep 10; done
	echo "transmission became responsive"
	output="$(echo "$torrent_list" | tail -n 2)"
	echo "$output"

	# get current listening port
	transmission_peer_port=$(transmission-remote $TRANSMISSION_RPC_PORT $myauth -si | grep Listenport | grep -oE '[0-9]+')
	if [[ "$new_port" != "$transmission_peer_port" ]]; then
		if [[ "true" = "$ENABLE_UFW" ]]; then
			echo "Update UFW rules before changing port in Transmission"

			echo "denying access to $transmission_peer_port"
			ufw deny "$transmission_peer_port"

			echo "allowing $new_port through the firewall"
			ufw allow "$new_port"
		fi

		echo "setting transmission port to $new_port"
		transmission-remote ${TRANSMISSION_RPC_PORT} ${myauth} -p "$new_port"

		echo "Checking port..."
		sleep 10
		transmission-remote ${TRANSMISSION_RPC_PORT} ${myauth} -pt
	else
		echo "No action needed, port hasn't changed"
	fi
}

# Check that natpmpc is inatalled.

which natpmpc 2>/dev/null
if [ $? -gt 0 ]; then
	echo "natpmpc is not installed. natpmpc is required to configure ProtonVPN port forwarding."
	echo "port forwarding for ProtonVPN has not been configured."
	exit 1
fi

echo "natpmpc installed and executable."

# the following is largely based on the instructions found here:
# https://protonvpn.com/support/port-forwarding-manual-setup/#linux
#

natpmpc -a 1 0 udp 60 -g 10.2.0.1
natpmpc -a 1 0 tcp 60 -g 10.2.0.1
while true; do
	date
	cmdoutput=$(natpmpc -a 1 0 udp 60 -g 10.2.0.1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1 || {
		echo -e "ERROR with natpmpc command \a"
		break
	})
	pf_port=$(echo $cmdoutput | grep -Eo 'Mapped public port ([0-9]*) protocol UDP' | grep -Eo '([0-9]{5})')
	if [ -z "$pf_port" ]; then
		echo "----------------------------"
		echo "No port retuned from natpmpc"
		echo "----------------------------"
	else
		bind_trans
		echo "----------------------------"
		echo "THE FORWARDED PORT IS: ${pf_port}"
		echo "----------------------------"
	fi

	sleep 45
done
