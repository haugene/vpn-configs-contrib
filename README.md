# OpenVPN providers config collection

This repository is a support-repo for: https://github.com/haugene/docker-transmission-openvpn
It is an effort to separate the development and maintenance of that project and the
VPN configs it relies on.

The split is thought to have multiple benefits. It will reduce noice in the main project and
hopefully create a meaningful separation that can make it easier to test changes in configs and contribute to keep the providers up to date.

This is a work in progress, and the README will be updated later...

## Structure

The plan as of now is to have one folder per technology, as Wireguard may also come into play later.

So the structure becomes something like:
```
<vpn-technology>/<provider>/<bundle-name>/configs.ovpn
```

Or examplified by:
```
openvpn/mullvad/tcp80/mullvad_ch_tcp80.ovpn
```

NOTE: This might also change based on development and discussions in https://github.com/haugene/docker-transmission-openvpn/issues/1489
