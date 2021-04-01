# OpenVPN providers config collection

This repository is a support-repo for: https://github.com/haugene/docker-transmission-openvpn
It is an effort to separate the development and maintenance of that project and the
VPN configs it relies on.

The split is thought to have multiple benefits. It will reduce noice in the main project and
hopefully create a meaningful separation that can make it easier to test changes in configs and contribute to keep the providers up to date.

This is a work in progress, and the README will be updated later...

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
| anonine | :sos: (28%) | 54 | 15 |
| anonvpn | :sos: (12%) | 8 | 1 |
| blackvpn | :sos: (0%) | 43 | 0 |
| btguard | :100: | 2 | 2 |
| cryptostorm | :sos: (0%) | 53 | 0 |
| expressvpn | :white_check_mark: (94%) | 148 | 139 |
| fastestvpn | :white_check_mark: (96%) | 114 | 110 |
| freevpn | :sos: (0%) | 29 | 0 |
| froot | :100: | 7 | 7 |
| frostvpn | :warning: (46%) | 275 | 127 |
| getflix | :white_check_mark: (99%) | 1377 | 1370 |
| ghostpath | :ok: (79%) | 90 | 71 |
| giganews | :white_check_mark: (99%) | 148 | 146 |
| hideme | :white_check_mark: (91%) | 64 | 58 |
| hidemyass | :ok: (74%) | 535 | 395 |
| integrityvpn | :100: | 1 | 1 |
| ironsocket | :white_check_mark: (98%) | 42 | 41 |
| ivacy | :ok: (70%) | 101 | 71 |
| ivpn | :white_check_mark: (96%) | 47 | 45 |
| mullvad | :100: | 49 | 49 |
| octanevpn | :ok: (76%) | 91 | 69 |
| ovpn | :100: | 4 | 4 |
| privado | :white_check_mark: (95%) | 188 | 178 |
| privatevpn | :ok: (78%) | 533 | 415 |
| protonvpn | :100: | 406 | 406 |
| proxpn | :sos: (12%) | 25 | 3 |
| purevpn | :ok: (80%) | 105 | 84 |
| ra4w | :ok: (77%) | 69 | 53 |
| safervpn | :warning: (46%) | 71 | 33 |
| slickvpn | :100: | 92 | 92 |
| smartdnsproxy | :white_check_mark: (98%) | 1281 | 1260 |
| smartvpn | :100: | 3 | 3 |
| surfshark | :white_check_mark: (95%) | 295 | 279 |
| tiger | :100: | 42 | 42 |
| torguard | :white_check_mark: (91%) | 53 | 48 |
| trustzone | :ok: (81%) | 70 | 57 |
| tunnelbear | :white_check_mark: (96%) | 23 | 22 |
| vpnac | :white_check_mark: (98%) | 385 | 379 |
| vpnarea | :warning: (64%) | 135 | 87 |
| vpnbook | :100: | 9 | 9 |
| vpnfacile | :100: | 55 | 55 |
| vpnht | :100: | 48 | 48 |
| vpntunnel | :100: | 126 | 126 |
| vpnunlimited | :white_check_mark: (99%) | 68 | 67 |
| windscribe | :white_check_mark: (98%) | 357 | 350 |
| zoogvpn | :sos: (0%) | 99 | 0 |

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
