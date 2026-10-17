# Private Internet Access (next-generation network)

# Description

This provider connects to PIA's next-generation network — the one PIA's own
[manual-connections](https://github.com/pia-foss/manual-connections) scripts target — by generating
configs at container start from PIA's
[server list](https://serverlist.piaservers.net/vpninfo/servers/v6) instead of shipping `.ovpn`
files. It exists alongside the older `pia` provider, which unpacks the config bundle from PIA's
website.

## Why use this instead of `pia`

The main reason is all of the official PIA clients and their reference [manual-connections](https://github.com/pia-foss/manual-connections) script prefer it currently. But there are a few more reasons: 

* **You know which server you are on.** The configs generated here name an exact IP, taken from the
  server list, which also tells us that host's certificate common name. The `pia` bundle connects to
  `<region>.privacy.network`, and that name resolves into a pool that is not the region's OpenVPN
  hosts. Resolving a few of them against the server list on the day this was written:
  `de-frankfurt.privacy.network` returned five addresses — one WireGuard/IKEv2 host for the region,
  one `meta` host belonging to a *different* region, and three that appear nowhere in the list at
  all; `swiss.privacy.network` returned two `meta` hosts and three unlisted addresses. Since the
  port forwarding API is served per server, whether it answers depends on which address you happened
  to get. Here it is the same machine every time, and its certificate is verified against the
  RSA-4096 CA shipped next to the script rather than trusted blindly.
* **The region list cannot go stale, and config names cannot move underneath you.** The bundle has
  been renamed before — both the zip URLs and the config names inside it — which broke people's
  `OPENVPN_CONFIG` values
  ([#1592](https://github.com/haugene/docker-transmission-openvpn/issues/1592)). The live list also
  simply has more in it: 189 regions offering OpenVPN, against 166 configs in the bundle (counted
  September 2026).
* **Better defaults.** The generated configs use aes-256-cbc with sha256 against the RSA-4096 CA.
  The bundle `pia` downloads by default is aes-128-cbc with sha1 on the RSA-2048 CA (its
  `openvpn-strong.zip` variant matches ours, but you have to ask for it).
* **The hardware is PIA's own.** PIA says of the next-generation servers: "We buy our own hardware,
  and use highly secure data centers to store and maintain each individual server", "All our servers
  are RAM-only", the OS is encrypted, and they run
  [10Gbps lines and network cards](https://www.privateinternetaccess.com/blog/pia-colocated-servers/).

Port forwarding does differ in implementation, if not in availability: the reservation here survives
container restarts (below), API calls verify TLS, and a lost forward stops the container instead of
leaving transmission listening on a port nobody forwards. The rewritten port forwarding script also properly fails on error with friendlier messages to help you debug what went wrong during port reservation.

## How it is put together

[configure-openvpn.sh](/openvpn/pia-nextgen/configure-openvpn.sh) fetches the server list at
container start and writes one config per region into the provider directory.
`strong.template` is the config body they are built from: PIA's own `openvpn_config/strong.ovpn`
with the container-specific bits changed. It deliberately has no `remote` line, which is why it is
not named `*.ovpn`.

# How to use this vpn provider

```bash
OPENVPN_PROVIDER=pia-nextgen
OPENVPN_USERNAME=xNNNNNNN
OPENVPN_PASSWORD=xxxxxxxxxxxxxxxxxx
OPENVPN_CONFIG=uk
```

Configs are named after the **region id** from the server list (`uk.ovpn`, `ca_toronto.ovpn`,
`de_berlin.ovpn`, …). The region *name* is also created, as a symlink to the region id, lowercased
with spaces turned into underscores — so `uk` is also reachable as `uk_london`. Those aliases are
the names PIA uses for the files in its own bundle, so a value carried over from the `pia` provider
almost always still works: 165 of the 166 configs in that bundle match an alias generated here (the
exception is `dk_copenhagen`, which the server list calls `denmark`).

If you do not set `OPENVPN_CONFIG` at all, `default.ovpn` is a symlink to a randomly chosen region,
picked fresh on every container start. The image's usual `OPENVPN_CONFIG` handling applies and works
nicely with region ids: give it a comma-separated list and one is chosen at random per start, or set
`OPENVPN_CONFIG_SEQUENTIAL=true` to walk the list in order.

Everything the provider generates lives inside the container, not on the `/config` volume: the image
copies this directory to `/etc/openvpn/pia-nextgen` on every start and the generated configs are
written there, so they never touch your checkout of this repository. That is also why the port
reservation is cached under `/config` instead (see below).

## Provider-specific environment variables

| Variable | Default | What it does |
| --- | --- | --- |
| `PIA_NEXTGEN_PROTOCOL` | `udp` | `udp` connects on port 8080, `tcp` on 8443 — the same ports PIA's `connect_to_openvpn_with_token.sh` uses. The server list advertises alternatives (853/123/53 for UDP, 80/443/853 for TCP) but this provider does not use them, and the legacy PIA ports (1197, 1198) belong to the old network, not this one. |
| `PIA_PF` | unset | Set to `true` to generate configs **only** for regions that advertise port forwarding. Useful as a guard so you cannot accidentally connect somewhere that cannot forward, at least according to the PIA API. |
| `PIA_PF_INSECURE` | `false` | Skip TLS verification of the port forwarding API. Only useful if PIA changes what the API presents; not a supported configuration. |
| `PIA_PF_REUSE` | `true` | Keep the port across container restarts by caching the reservation. Set to `false` to get a new port on every start; nothing is then read from or written to `PIA_PF_STATE_FILE`. |
| `PIA_PF_STATE_FILE` | `/config/pia-nextgen-portforward.json` | Where the cached port reservation is stored. Ignored when `PIA_PF_REUSE=false`. |

Note that the container needs outbound network access *before* the tunnel comes up, since the server
list is fetched while the config is being generated. If your firewall blocks that, startup fails
with an empty server list.

# Port forwarding

The image runs `update-port.sh` on its own as soon as it sees one in the provider directory, so
there is nothing to switch on — set `DISABLE_PORT_UPDATER=true` if you want it *off*. What you do
have to do is connect to a region that supports forwarding. As of September 2026, 134 of the 189
regions advertise it, but none of the 55 US regions do, so a US region will start the tunnel and
then fail the port forwarder. Set `PIA_PF=true` to keep the regions without it out of the list
entirely.

How it works, and what is worth knowing about it:

* PIA hands out a base64 **payload** (your port plus an expiry, roughly two months out) and a
  **signature** proving the payload came from PIA. That pair *is* the reservation, and it is not tied
  to the server that issued it.
* Because of that, the reservation is cached in `PIA_PF_STATE_FILE` on the `/config` volume and
  reused across container restarts — and even across regions — instead of burning a new port every
  time. PIA exposes the same idea as `PAYLOAD_AND_SIGNATURE` in `port_forwarding.sh`. You keep the
  same port for the life of the reservation, which is renewed a day before it expires. Set
  `PIA_PF_REUSE=false` if you would rather have a new port on every start; the cache is then bypassed
  in both directions, and an existing state file is left alone rather than read.
* The port must be re-bound at least every 15 minutes or PIA drops it. `update-port.sh` refreshes it
  every 15 minutes for as long as the container runs.
* If a refresh fails the reservation is gone, and the container **stops** rather than leave
  transmission listening on a port that is no longer forwarded.
* Some regions advertise `port_forward: true` in the server list but do not actually serve forwards.
  If `getSignature` fails or no API answers, try another region.

The generated configs carry two extra comment lines that `update-port.sh` reads back, so a config
you hand-copied from elsewhere will not work with the port forwarder unless it has them:

```
; pia_cn <server common name>    # verified against the port forwarding API certificate
; pia_region <region id>
```

`configure-openvpn.sh` also writes `pia-nextgen.env` next to the configs, because the image only
persists an allowlist of variables into the environment `update-port.sh` runs under (`CONFIG` and
`ENABLE_UFW` are on it; `VPN_PROVIDER_HOME` and the `PIA_*` settings are not). Both files are
regenerated on every start; nothing there is meant to be edited by hand.

## How to get a list of available configs

The following commands will give you a list of available configs for this provider. The first column is the region id, the second column is the region name and the third column indicates if the server supports port forwarding (pf) or not (-). Since all names are aliased to the region id you can use either the region id or the region name in the `OPENVPN_CONFIG` variable.

UDP servers:

```bash
curl -s https://serverlist.piaservers.net/vpninfo/servers/v6 | head -1 | jq -r '
.regions[]
| select(.servers.ovpnudp) 
| [.id, (.name|ascii_downcase|gsub(" ";"_")), (if .port_forward then "pf" else "-" end)]
| @tsv
' | sort | column -t
```

TCP servers:

```bash
curl -s https://serverlist.piaservers.net/vpninfo/servers/v6 | head -1 | jq -r '
.regions[]
| select(.servers.ovpntcp)
| [.id, (.name|ascii_downcase|gsub(" ";"_")), (if .port_forward then "pf" else "-" end)]
| @tsv
' | sort | column -t
```

To list only the regions that advertise port forwarding, add `| select(.port_forward)` after the
`.regions[]` line.

## Example

```yaml
environment:
  - OPENVPN_PROVIDER=pia-nextgen
  - OPENVPN_CONFIG=ca_toronto
  - OPENVPN_USERNAME=xNNNNNNN
  - OPENVPN_PASSWORD=xxxxxxxxxxxxxxxxxx
  - PIA_NEXTGEN_PROTOCOL=udp
  - PIA_PF=true
  - LOCAL_NETWORK=192.168.1.0/24
```
