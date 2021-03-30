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

## Config testing

There is a work in progress to automate periodic checks of all our configs.
This will not be a perfect process and the only way to ensure that a config works as it should is to have an active
subscription with the relevant provider and see that a connection is established and Transmission is running as it should.

Some testing is better than none, and we believe that it could give us a hint about the state of the providers.

### Running the tests

The tests are planned to be run on a GitHub workflow and the results should be stored for future aggregation.
Hopefully we can also use it to generate a markdown table with the key info and some traffic light indication
of the state of the providers. Let's see where it goes. If you have Python experience, help is welcomed :)

For now the tests are run in a simple setup with docker-compose. We throw the configs from this repo into
the main project container and mount our test script and fire it off. The results are written to a data folder
mounted from this folder.

Start it locally by running:
```
docker-compose -f configtest-compose.yml up
```
