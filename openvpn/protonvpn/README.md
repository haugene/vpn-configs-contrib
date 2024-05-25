# Port Forwarding with ProtonVPN

Port forwarding for ProtonVPN has been implemented in this [update-port.sh](/openvpn/protonvpn/update-port.sh) script. The novel part of this script is based on the [port forwarding instructions from ProtonVPN](https://protonvpn.com/support/port-forwarding-manual-setup/#linux). 

## Requirements:
- an account with ProtonVPN
- a build of haugene/docker-transmission-openvpn that has natpmpc installed.
  - The dev branch of haugene/docker-transmission-docker has the natpmpc install. As of 2023-11-19, it is not yet in the master branch and/or the published image.
  - If your transmission container does not have natpmpc then transmission will still work - you just will not be using port-forwarding.
  - The brave may manually install natpmpc inside their transmission-openvpn container.
  - The less brave will need to wait until the published image of docker-transmission-openvpn has natpmpc.


## Notes:
This script has been manually tested to work with the following ProtonVPN configs that are included in this repo.:
- ch.protonvpn.udp
- es.protonvpn.tcp
- es.protonvpn.udp
- fr.protonvpn.udp
- fr.protonvpn.udp
- is.protonvpn.tcp
- is.protonvpn.udp
- nl.protonvpn.tcp
- nl.protonvpn.udp
- ro.protonvpn.udp
- ro.protonvpn.tcp
- se.protonvpn.tcp
- se.protonvpn.udp
- uk.protonvpn.udp

## Environment Variables for transmission-openvpn
```
environment:
  - PUID=[PUID]
  - PGID=[PGID]
  - OPENVPN_CONFIG=uk.protonvpn.udp
  - OPENVPN_PROVIDER=PROTONVPN
  - OPENVPN_USERNAME=[OpenVPN / IKEv2 username] # See here: https://account.protonvpn.com/account
  - OPENVPN_PASSWORD=[OpenVPN / IKEv2 password] # See here: https://account.protonvpn.com/account
  - LOCAL_NETWORK=[your local network]/24 
  - DISABLE_PORT_FORWARDER=false
  - OPENVPN_OPTS=--inactive 3600 --ping 10 --ping-exit 60
...   
```

> Note that in order to use ProtonVPN port forwarding functionality it is mandatory to use the sufix `+pmp` in the username field. For example: if your username is `protonvpnuser` you should use `protonvpnuser+pmp`. If not, you will get `readnatpmpresponseorretry() failed : the gateway does not support nat-pmp` error.
