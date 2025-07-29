#!/bin/bash

set -e

# If the script is called from elsewhere
cd "${0%/*}"

# Delete everything (not this script though)
find . ! -name '*.sh' -delete

# Get updated configuration zip from TorGuard
curl -L https://privado.io/apps/ovpn_configs.zip -o privado_configs.zip &&
	unzip -j privado_configs.zip && rm -f privado_configs.zip

# Delete "tcp-scramble" files
rm -f ./*.tcp-scramble.ovpn

for f in *.default.ovpn; do
	fn="${f%.default.ovpn}.ovpn"
	# Strip out ".default" from filenames
	mv -- "$f" "$fn"
	# Update configs with correct paths
	sed -i "s/auth-user-pass/auth-user-pass \/config\/openvpn-credentials.txt/" "$fn"
done

# Create symlink for default.ovpn using the first ams-XXX.ovpn file
files=(ams-*.ovpn)
ln -sf "${files[1]}" default.ovpn
