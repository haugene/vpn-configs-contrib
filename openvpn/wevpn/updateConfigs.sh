#!/bin/bash

# You need to first download all configuration files from WeVPN manually,
# because they don't have a bulk download URL.
# Once all the .ovpn config files are downloaded

set -e

# Remove <cert>...</cert> part
sed -i '/^<cert>/,/^<\/cert>/d' *.ovpn

# Remove <key>...</key> part
sed -i '/^<key>/,/^<\/key>/d' *.ovpn

# Select a random server as default.ovpn
ln -sf "$(find . -name "*.ovpn" | shuf -n 1)" ./default.ovpn
