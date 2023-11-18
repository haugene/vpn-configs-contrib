# OpenVPN providers config collection

This repository is a support-repo for: https://github.com/haugene/docker-transmission-openvpn
It is an effort to separate the development and maintenance of that project and the
VPN configs it relies on.

The split is thought to have multiple benefits. It will reduce noice in the main project and
hopefully create a meaningful separation that can make it easier to test changes in configs and contribute to keep the providers up to date.

## Use your own config

If you have a `.ovpn` file from your VPN provider and you want to use it with this project
then [CONTRIBUTING.md](CONTRIBUTING.md) is the guide you're looking for.

## Structure

The main project currently only support OpenVPN but we're hoping to support Wireguard as well.
To plan for that we are separating configs here based on technology and then provider.

So the structure becomes:
```
<vpn-technology>/<provider>/<bundle-name>/configs.ovpn
```

For example:
```
openvpn/mullvad/tcp80/mullvad_ch_tcp80.ovpn
```

## Providers and status of configs

| Provider Folder | Provider Status | Configs tested | Successful |
| :-------------- | :-------------: | :------------: | :--------: |
| anonine | :sos: (0%) | 10 | 0 |
| anonvpn | :sos: (0%) | 8 | 0 |
| blackvpn | :sos: (0%) | 10 | 0 |
| btguard | :100: | 2 | 2 |
| bulletvpn | :ok: (70%) | 10 | 7 |
| cryptostorm | :100: | 10 | 10 |
| expressvpn | :white_check_mark: (90%) | 10 | 9 |
| fastestvpn | :ok: (80%) | 10 | 8 |
| freevpn | :sos: (0%) | 10 | 0 |
| froot | :100: | 7 | 7 |
| frostvpn | :sos: (0%) | 10 | 0 |
| getflix | :ok: (80%) | 10 | 8 |
| ghostpath | :ok: (70%) | 10 | 7 |
| giganews | :100: | 10 | 10 |
| goosevpn | :warning: (60%) | 10 | 6 |
| hideme | :ok: (80%) | 10 | 8 |
| hotspotshield | :100: | 10 | 10 |
| integrityvpn | :100: | 1 | 1 |
| ironsocket | :ok: (80%) | 10 | 8 |
| ivacy | :white_check_mark: (90%) | 10 | 9 |
| ivpn | :100: | 10 | 10 |
| mullvad | :ok: (70%) | 10 | 7 |
| octanevpn | :ok: (70%) | 10 | 7 |
| ovpn | :ok: (80%) | 10 | 8 |
| privado | :ok: (70%) | 10 | 7 |
| privatevpn | :ok: (80%) | 10 | 8 |
| protonvpn | :100: | 10 | 10 |
| proxpn | :sos: (0%) | 10 | 0 |
| purevpn | :100: | 10 | 10 |
| ra4w | :sos: (0%) | 10 | 0 |
| safervpn | :warning: (50%) | 10 | 5 |
| slickvpn | :ok: (70%) | 10 | 7 |
| slickvpncore | :white_check_mark: (90%) | 10 | 9 |
| smartdnsproxy | :ok: (80%) | 10 | 8 |
| smartvpn | :warning: (33%) | 3 | 1 |
| surfshark | :100: | 10 | 10 |
| tiger | :sos: (0%) | 10 | 0 |
| torguard | :ok: (70%) | 10 | 7 |
| trustzone | :sos: (0%) | 10 | 0 |
| tunnelbear | :ok: (80%) | 10 | 8 |
| vpnac | :100: | 10 | 10 |
| vpnarea | :warning: (60%) | 10 | 6 |
| vpnbook | :100: | 9 | 9 |
| vpnfacile | :sos: (0%) | 10 | 0 |
| vpnht | :sos: (0%) | 10 | 0 |
| vpntunnel | :ok: (80%) | 10 | 8 |
| vpnunlimited | :ok: (87%) | 77 | 67 |
| wevpn | :100: | 10 | 10 |
| windscribe | :warning: (60%) | 10 | 6 |
| zoogvpn | :sos: (0%) | 10 | 0 |


## Config testing

There is a work in progress to automate periodic checks of all our configs. The table above is the current
output of that work. As we can't automate this completely without having an active subscription to every supported
provider we do basic connectivity tests to assert the overall health of the providers and config bundles.

Some testing is better than none, and we believe that this will help maintain and manage providers going forward.

If you have Python experience and want to contribute - you're more than welcome! Create an issue and we can
start a discussion on what the next steps are. They're just runnung locally for now, but we plan
to move them into a CI. Probably GitHub workflows.

### Running the tests

For now the tests are run in a simple setup with docker-compose. We throw the configs from this repo into
the main project container, mount the test script and override the container command.
The results are written to a data folder mounted in the current location. Results will be owned by root for now,
we'll address that later. For now `sudo chown` is your friend.

Start it locally by running:
```
docker-compose -f configtest-compose.yml up
```
Then you can generate the markdown table by running:
```
python3 generate_results_md_table.py data/result1234.json >> README.md
```
Or something similar depending on the data file you want to use.