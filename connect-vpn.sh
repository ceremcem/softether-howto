#!/bin/bash
set -u -o pipefail
safe_source () { [[ ! -z ${1:-} ]] && source $1; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _sdir=$(dirname "$(readlink -f "$0")"); }; safe_source
# end of bash boilerplate

get_external_ip(){
    wget -qO- http://ipecho.net/plain
}

VPN_CMD="$_sdir/../vpnclient/vpncmd localhost /client /cmd"

cfg="$_sdir/config.sh"

if [[ ! -f $cfg ]]; then
    echo "ERROR: No configuration file found."
    echo "Copy the config.sh.sample as config.sh and edit accordingly"
    exit 5
fi
safe_source $cfg

LOCAL_GATEWAY_IP="$(ip route | grep default | cut -d' ' -f 3)"
PRODUCED_NIC_NAME="vpn_${NIC_NAME}"

# Create the NIC
if ! ifconfig $PRODUCED_NIC_NAME &> /dev/null; then
    $VPN_CMD NicCreate $NIC_NAME
else
    echo "* NIC \"$PRODUCED_NIC_NAME\" seems already created."
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

    $VPN_CMD AccountPassword ${ACCOUNT_NAME} /PASSWORD:${VPN_PASSWORD} /TYPE:radius
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
sudo dhclient $PRODUCED_NIC_NAME

echo "Altering routing table to use VPN server as gateway"
sudo ip route add $SERVER_IP/32 via $LOCAL_GATEWAY_IP
sudo route add default gw $VPN_GATEWAY_IP
sudo ip route del default via $LOCAL_GATEWAY_IP

cleanup(){
    echo
    echo "Restoring previous routing table settings"
    sudo route del default
    sudo ip route del $SERVER_IP/32
    sudo ip route add default via $LOCAL_GATEWAY_IP
    echo "Current external ip: $(get_external_ip)"
}

trap cleanup EXIT

echo "-----------------------------------"
echo "Current external ip: $(get_external_ip)"
if [[ "$(get_external_ip)" = "$SERVER_IP" ]]; then
    echo "...succesfully connected to VPN"
else
    echo "...something went wrong!"
fi

echo
echo "Press Ctrl+C to disconnect from VPN"
echo "-----------------------------------"
sleep infinity
