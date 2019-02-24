#!/bin/bash
set -u -o pipefail
safe_source () { [[ ! -z ${1:-} ]] && source $1; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _sdir=$(dirname "$(readlink -f "$0")"); }; safe_source
# end of bash boilerplate

get_external_ip(){
    wget -qO- http://ipecho.net/plain
}

INSTALL_DIR="$_sdir/../vpnclient"

VPN_CMD="$INSTALL_DIR/vpncmd localhost /client /cmd"
VPN_CLIENT="$INSTALL_DIR/vpnclient"

cfg="$_sdir/config.sh"

if [[ ! -f $cfg ]]; then
    echo "ERROR: No configuration file found."
    echo "Copy the config.sh.sample as config.sh and edit accordingly"
    exit 5
fi
safe_source $cfg

LOCAL_GATEWAY_IP="$(ip route | grep default | cut -d' ' -f 3)"
PRODUCED_NIC_NAME="vpn_${NIC_NAME}"

get_vpn_ip(){
    ifconfig $PRODUCED_NIC_NAME | grep 'inet.*netmask' | awk '{print $2}'
}

cleanup(){
    echo
    echo "Restoring previous routing table settings"
    sudo route del default
    sudo ip route del $SERVER_IP/32
    sudo ip route add default via $LOCAL_GATEWAY_IP
    echo "Disconnecting from VPN"
    $VPN_CMD AccountDisconnect ${ACCOUNT_NAME}
    sudo $VPN_CLIENT stop
    echo "Current external ip: $(get_external_ip)"
}

trap cleanup EXIT


if ! $VPN_CMD check &> /dev/null; then
    echo "INFO: vpnclient isn't running, starting client."
    sudo $VPN_CLIENT start
fi

# Create the NIC
if ifconfig $PRODUCED_NIC_NAME &> /dev/null; then
    echo "* NIC \"$PRODUCED_NIC_NAME\" seems already created."
else
    $VPN_CMD NicCreate $NIC_NAME
fi

# Create the account
if $VPN_CMD AccountGet ${ACCOUNT_NAME} &> /dev/null; then
    echo "* Account \"${ACCOUNT_NAME}\" seems already created."
else
    $VPN_CMD AccountCreate ${ACCOUNT_NAME} \
        /SERVER:${SERVER_IP}:${SERVER_PORT} \
        /HUB:${HUB_NAME} \
        /USERNAME:${VPN_USERNAME} \
        /NICNAME:${NIC_NAME}

    $VPN_CMD AccountPassword ${ACCOUNT_NAME} \
        /PASSWORD:${VPN_PASSWORD} \
        /TYPE:radius
fi

# Connect to VPN
if $VPN_CMD AccountStatusGet ${ACCOUNT_NAME} &> /dev/null; then
    echo "* Account \"${ACCOUNT_NAME}\" seems connected."
else
    $VPN_CMD AccountConnect ${ACCOUNT_NAME}
fi

# Set up the routing table
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
echo "Requesting IP with dhclient:"
#sudo dhclient -r # <- this command ruins the connection
sudo timeout 20s dhclient $PRODUCED_NIC_NAME
[[ $? -eq 0 ]] || { echo "Failed to get DHCP response"; exit 5; }

echo "Altering routing table to use VPN server as gateway"
sudo ip route add $SERVER_IP/32 via $LOCAL_GATEWAY_IP
sudo route add default gw $VPN_GATEWAY_IP
sudo ip route del default via $LOCAL_GATEWAY_IP


echo "-----------------------------------"
echo "Current external ip: $(get_external_ip)"
if [[ "$(get_external_ip)" = "$SERVER_IP" ]]; then
    echo "...succesfully connected to VPN"
    echo "Client IP: $(get_vpn_ip)"
else
    echo "...something went wrong!"
fi

echo
echo "Press Ctrl+C to disconnect from VPN"
echo "-----------------------------------"
sleep infinity
