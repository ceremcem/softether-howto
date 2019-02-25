#!/bin/bash
set -u -o pipefail
safe_source () { [[ ! -z ${1:-} ]] && source $1; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _sdir=$(dirname "$(readlink -f "$0")"); }; safe_source
# end of bash boilerplate

get_external_ip(){
    timeout 5s wget -qO- http://ipecho.net/plain -o /dev/null
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


is_ip_reachable(){
    # returns: boolean
    local ip="$1"
    for i in `seq 1 5`; do
        if timeout 0.2s ping -c 1 "$ip" &> /dev/null; then
            # immediately return if succeeded
            return 0
        fi
    done
    return 2
}

is_internet_reachable() {
    is_ip_reachable "8.8.8.8"
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

LOCAL_GATEWAY_IP="$(ip route | grep default | awk '{print $3}' | head -n1)"
PRODUCED_NIC_NAME="vpn_${NIC_NAME}"

echo "Using local gateway IP: $LOCAL_GATEWAY_IP"

get_vpn_ip(){
    ip address show $PRODUCED_NIC_NAME | grep "inet\W" | awk '{print $2}' | cut -d/ -f1
}

is_gateway_reachable(){
    is_ip_reachable "$VPN_GATEWAY_IP"
}


cleanup(){
    echo
    echo "Restoring previous routing table settings"
    ip route del $SERVER_IP/32
    ip route chg default via $LOCAL_GATEWAY_IP
    echo "Disconnecting from VPN"
    $VPN_CMD AccountDisconnect ${ACCOUNT_NAME} > /dev/null
    $VPN_CLIENT stop
    echo "Current external ip: $(get_external_ip)"
}

trap cleanup EXIT


if ! $VPN_CMD check &> /dev/null; then
    echo "INFO: vpnclient isn't running, starting client."
    $VPN_CLIENT start
fi

# Create the NIC
if ip address show dev $PRODUCED_NIC_NAME &> /dev/null; then
    echo "* NIC \"$PRODUCED_NIC_NAME\" seems already created."
else
    echo "+ Creating NIC: \"$NIC_NAME\"..."
    $VPN_CMD NicCreate $NIC_NAME > /dev/null
fi

# Create the account
if $VPN_CMD AccountGet ${ACCOUNT_NAME} &> /dev/null; then
    echo "* Account \"${ACCOUNT_NAME}\" seems already created."
else
    echo "+ Creating Account: \"$ACCOUNT_NAME\"..."
    $VPN_CMD AccountCreate ${ACCOUNT_NAME} \
        /SERVER:${SERVER_IP}:${SERVER_PORT} \
        /HUB:${HUB_NAME} \
        /USERNAME:${VPN_USERNAME} \
        /NICNAME:${NIC_NAME} > /dev/null

    $VPN_CMD AccountPassword ${ACCOUNT_NAME} \
        /PASSWORD:${VPN_PASSWORD} \
        /TYPE:radius > /dev/null
fi

# Connect to VPN
if $VPN_CMD AccountStatusGet ${ACCOUNT_NAME} &> /dev/null; then
    echo "* Account \"${ACCOUNT_NAME}\" seems connected."
else
    echo "+ Connecting to account: \"$ACCOUNT_NAME\"..."
    $VPN_CMD AccountConnect ${ACCOUNT_NAME} > /dev/null
fi

# Set up the routing table
echo 1 | tee /proc/sys/net/ipv4/ip_forward > /dev/null
echo "Requesting IP with dhclient:"
#sudo dhclient -r # <- this command ruins the connection
timeout 20s dhclient $PRODUCED_NIC_NAME
[[ $? -eq 0 ]] || { echo "Failed to get DHCP response"; exit 5; }

echo "Altering routing table to use VPN server as gateway"
ip route add $SERVER_IP/32 via $LOCAL_GATEWAY_IP
ip route chg default via $VPN_GATEWAY_IP

is_external_ip_correct(){
    if [[ "$(get_external_ip)" = "$SERVER_IP" ]]; then
        return 0
    else
        return 5
    fi
}

echo "-----------------------------------"
echo -n "Current external ip: $(get_external_ip)"
if is_external_ip_correct; then
    echo "  [Correct]"
    echo "Client IP: $(get_vpn_ip)"
else
    echo "  [WRONG!]"
    echo "Exiting..."
    exit 5
fi

echo
echo "Press Ctrl+C to disconnect from VPN"
echo "-----------------------------------"
vpn_reachable=true
while :; do
    if [[ -z $(get_vpn_ip) ]]; then
        echo_stamp "VPN IP is lost!"
        timeout 20s dhclient $PRODUCED_NIC_NAME &> /dev/null
        [[ $? -eq 0 ]] && echo_stamp "Reconnected."
        echo "====================================="
        continue
    fi

    # log vpn gateway connection states
    if ! is_gateway_reachable && [[ $vpn_reachable = true ]]; then
        echo_stamp "VPN gateway unreachable!"
        vpn_reachable=false
    else
        if [[ $vpn_reachable = false ]]; then
            echo_stamp "VPN gateway is now reachable."
        fi
        vpn_reachable=true
    fi

    sleep 2s
done
