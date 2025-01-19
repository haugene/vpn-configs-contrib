#!/bin/bash

set -e

# If the script is called from elsewhere
cd "$(dirname "$0")"

# Delete everything (not this script though)
find . ! -name '*.sh' -delete

# Get updated configuration zip from TorGuard
curl -L https://privado.io/apps/ovpn_configs.zip -o privado_configs.zip &&
	unzip -j privado_configs.zip && rm -f privado_configs.zip

# Delete "tcp-scramble" files
rm -f *.tcp-scramble.ovpn

# Strip out ".default" from filenames
for f in *.default.ovpn; do mv -- "$f" "${f%.default.ovpn}.ovpn"; done

# Update configs with correct paths
sed -i "s/auth-user-pass/auth-user-pass \/config\/openvpn-credentials.txt/" *.ovpn

# Create symlink for default.ovpn
ln -s ams-005.ovpn default.ovpn

# Remove existing default symlinks (XXX.ovpn)
rm -f ???.ovpn

# Link default config for each server (ams-XXX.ovpn -> ams.ovpn)
for f in *.ovpn; do
	if [ ! -e "${f:0:3}.ovpn" ]; then
		ln -sf "$f" "${f:0:3}.ovpn"
	fi
done
