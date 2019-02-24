#!/bin/bash
set -u -o pipefail
safe_source () { [[ ! -z ${1:-} ]] && source $1; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _sdir=$(dirname "$(readlink -f "$0")"); }; safe_source
# end of bash boilerplate

get_external_ip(){
    timeout 5s wget -qO- http://ipecho.net/plain
}

nudo(){
    # normal user do
    sudo -i -u $SUDO_USER "$@"
}

# copy/paste from aktos-bash-lib
echo_stamp () {
  local MESSAGE="$(date +'%F %H:%M:%S') - $@"
  echo $MESSAGE
}
# end of copy/paste from aktos-bash-lib

is_network_reachable() {
    # returns: boolean
    if ping -c1 -w1 8.8.8.8 &> /dev/null; then
        return 0
    else
        echo "DEBUG: re-checking connectivity"
        sleep 2
        ping -c1 -w1 8.8.8.8 &> /dev/null
    fi
}


INSTALL_DIR="$_sdir/../vpnclient"

VPN_CMD="nudo $INSTALL_DIR/vpncmd localhost /client /cmd"
VPN_CLIENT="$INSTALL_DIR/vpnclient"

cfg="$_sdir/config.sh"

if [[ ! -f $cfg ]]; then
    echo "ERROR: No configuration file found."
    echo "Copy the config.sh.sample as config.sh and edit accordingly"
    exit 5
fi
safe_source $cfg


# All checks are done, run as root.
[[ $(whoami) = "root" ]] || { sudo $0 "$@"; exit 0; }

LOCAL_GATEWAY_IP="$(ip route | grep default | cut -d' ' -f 3)"
PRODUCED_NIC_NAME="vpn_${NIC_NAME}"

get_vpn_ip(){
    ifconfig $PRODUCED_NIC_NAME | grep 'inet.*netmask' | awk '{print $2}'
}

cleanup(){
    echo
    echo "Restoring previous routing table settings"
    route del default
    ip route del $SERVER_IP/32
    ip route add default via $LOCAL_GATEWAY_IP
    echo "Disconnecting from VPN"
    $VPN_CMD AccountDisconnect ${ACCOUNT_NAME}
    $VPN_CLIENT stop
    echo "Current external ip: $(get_external_ip)"
}

trap cleanup EXIT


if ! $VPN_CMD check &> /dev/null; then
    echo "INFO: vpnclient isn't running, starting client."
    $VPN_CLIENT start
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
echo 1 | tee /proc/sys/net/ipv4/ip_forward > /dev/null
echo "Requesting IP with dhclient:"
#sudo dhclient -r # <- this command ruins the connection
timeout 20s dhclient $PRODUCED_NIC_NAME
[[ $? -eq 0 ]] || { echo "Failed to get DHCP response"; exit 5; }

echo "Altering routing table to use VPN server as gateway"
ip route add $SERVER_IP/32 via $LOCAL_GATEWAY_IP
route add default gw $VPN_GATEWAY_IP
ip route del default via $LOCAL_GATEWAY_IP

is_external_ip_correct(){
    if [[ "$(get_external_ip)" = "$SERVER_IP" ]]; then
        return 0
    else
        return 5
    fi
}

echo "-----------------------------------"
echo "Current external ip: $(get_external_ip)"
if is_external_ip_correct; then
    echo "...succesfully connected to VPN"
    echo "Client IP: $(get_vpn_ip)"
else
    echo "...something went wrong!"
    exit 5
fi

echo
echo "Press Ctrl+C to disconnect from VPN"
echo "-----------------------------------"
while :; do
    if [[ -z $(get_vpn_ip) ]]; then
        echo_stamp "Connection seems to be lost!"
        timeout 20s dhclient $PRODUCED_NIC_NAME &> /dev/null
        [[ $? -eq 0 ]] && echo_stamp "Reconnected."
        echo "====================================="
        continue
    fi
    sleep 2s
done
