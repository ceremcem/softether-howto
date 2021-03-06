#!/bin/bash
set -u -o pipefail
safe_source () { [[ ! -z ${1:-} ]] && source $1; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _sdir=$(dirname "$(readlink -f "$0")"); }; safe_source
# end of bash boilerplate

# see "killing timeout": https://unix.stackexchange.com/a/57692/65781
declare -a timeout_pids
exec 21>&1; exec 22>&2 # backup file descriptors, see https://superuser.com/a/1446738/187576
my_timeout(){
    local args tp ret
    args="$@"
    timeout $args &
    tp=$!
    #echo "pid of timeout: $tp"
    timeout_pids+=($tp)
    wait $tp
    ret=$?
    count=${#timeout_pids[@]}
    for ((i = 0; i < count; i++)); do
        if [ "${timeout_pids[i]}" = "$tp" ] ; then
            unset 'timeout_pids[i]'
        fi
    done
    return $ret
}

get_external_ip(){
    my_timeout 15s wget -qO- http://ipecho.net/plain -o /dev/null
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
    local failed_before=false
    for i in `seq 1 3`; do
        # FIXME: https://superuser.com/q/1446588/187576
        if my_timeout 9s ping -c 1 "$ip" &> /dev/null; then
            # immediately return if succeeded
            if $failed_before; then
                echo_stamp "successfully ping to $ip"
            fi
            return 0
        else
            failed_before=true
            echo_stamp "trying to get a successful ping to $ip"
        fi
    done
    return 2
}

is_internet_reachable() {
    is_ip_reachable "8.8.8.8"
}


if command -v vpnclient > /dev/null; then
    INSTALL_DIR=
else
    INSTALL_DIR="$_sdir/../vpnclient/"
    [[ -d $INSTALL_DIR ]] || { echo "SoftEther client not found."; exit 5; }
fi

VPN_CMD="nudo ${INSTALL_DIR}vpncmd localhost /client /cmd"
VPN_CLIENT="${INSTALL_DIR}vpnclient"

cfg="${1:-}"

if [[ ! -f $cfg ]]; then
    echo "ERROR: No configuration file found."
    echo
    echo "Copy the sample.config as your.config and edit accordingly"
    exit 5
fi
safe_source $cfg

# All checks are done, run as root.
[[ $(whoami) = "root" ]] || { sudo $0 "$@"; exit 0; }

echo "Using configuration file: $cfg"

LOCAL_GATEWAY_IP=
PRODUCED_NIC_NAME="vpn_${NIC_NAME}"

routing_table_altered=false


get_vpn_ip(){
    ip address show $PRODUCED_NIC_NAME | grep "inet\W" | awk '{print $2}' | cut -d/ -f1
}

is_gateway_reachable(){
    is_ip_reachable "$VPN_GATEWAY_IP"
}


cleanup(){
    [[ $routing_table_altered == false ]] && return 0;
    echo "-----------------------------------------"
    echo "Restoring previous routing table settings"
    ip route del $SERVER_IP/32
    ip route chg default via $LOCAL_GATEWAY_IP
    echo "Disconnecting from VPN"
    $VPN_CMD AccountDisconnect ${ACCOUNT_NAME} > /dev/null
    $VPN_CLIENT stop
    dhclient -r $PRODUCED_NIC_NAME
    dhclient $prev_dhclient_iface
    echo "Current external ip: $(get_external_ip)"
}

pre_cleanup(){
    exec 1>&21; exec 2>&22 # restore file descriptors, see https://superuser.com/a/1446738/187576
    echo "Executing pre-cleanup..."
    for i in "${timeout_pids[*]}"; do
        if [[ ! -z $i ]]; then
            echo "Killing PID: $i"
            kill -INT -$i 2> /dev/null
        fi
    done
    exit
}

trap pre_cleanup INT
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
    # test newly created NIC
    ip addr show $PRODUCED_NIC_NAME > /dev/null
    if [[ $? != 0 ]]; then
        echo "!!! Failed to create Virtual Network Adapter $PRODUCED_NIC_NAME"
        exit 5
    fi
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


# Set up the routing table
echo 1 | tee /proc/sys/net/ipv4/ip_forward > /dev/null

# Connect/reconnect to VPN
prev_dhclient_iface=
ifaces=( $(ip addr list | awk -F': ' '/^[0-9]/ {print $2}') )
for i in ${ifaces[@]}; do
    while read -r d; do
         if `echo $d | grep -w "$i" > /dev/null`; then
             prev_dhclient_iface="$i"
             break 2
         fi
    done <<< "$(ps --no-headers $(pgrep dhclient))"
done

reconnect_to_vpn(){
    routing_table_altered=true
    while :; do
        LOCAL_GATEWAY_IP="$(ip route | grep default | awk '{print $3}' | head -n1)"
        if [[ -z $LOCAL_GATEWAY_IP ]]; then
            echo "No local gateway IP found, waiting..."
            my_timeout 20s dhclient $prev_dhclient_iface
            sleep 2
        else
            break
        fi
    done
    echo "Using local gateway IP: $LOCAL_GATEWAY_IP"

    if $VPN_CMD AccountStatusGet ${ACCOUNT_NAME} &> /dev/null; then
        echo "* Account \"${ACCOUNT_NAME}\" seems connected."
    else
        echo "+ Connecting to account: \"$ACCOUNT_NAME\"..."
        $VPN_CMD AccountConnect ${ACCOUNT_NAME} > /dev/null
    fi

    echo "Setting up VPN IP for $PRODUCED_NIC_NAME:"
    if [[ ! -z $prev_dhclient_iface ]]; then
        echo "(re-requesting dhcp address for previous iface: $prev_dhclient_iface)"
        dhclient -r $prev_dhclient_iface
        my_timeout 20s dhclient $prev_dhclient_iface
    fi

    echo "...requesting VPN IP"
    dhclient -r $PRODUCED_NIC_NAME
    my_timeout 20s dhclient $PRODUCED_NIC_NAME
    [[ $? -eq 0 ]] || { echo "Failed to get DHCP response"; return 5; }

    echo "Altering routing table to use VPN server as gateway"
    ip route add $SERVER_IP/32 via $LOCAL_GATEWAY_IP
    ip route chg default via $VPN_GATEWAY_IP

    echo "-----------------------------------"
    current_ip="$(get_external_ip)"
    echo -n "Current external ip: $current_ip"
    if [[ "$current_ip" = "${SERVER_IP}" ]]; then
        echo " [Correct]"
        echo "Client IP: $(get_vpn_ip)"
    else
        echo " [WRONG: $current_ip]"
        echo "Exiting..."
        return 5
    fi
}

# Connect for the first time
reconnect_to_vpn
echo
echo "Press Ctrl+C to disconnect from VPN"
echo "-----------------------------------"


vpn_reachable=true
while :; do
    if [[ -z $(get_vpn_ip) ]]; then
        echo_stamp "VPN IP is lost!"
    fi

    # log vpn gateway connection states
    if ! is_gateway_reachable; then
        /home/ceremcem/.sbin/bell 2> /dev/null
        echo_stamp "VPN gateway seems unreachable, reconnecting"
        reconnect_to_vpn
        if $vpn_reachable; then
            vpn_reachable=false
            echo_stamp "VPN gateway unreachable!"
        fi
    else
        if ! $vpn_reachable; then
            vpn_reachable=true
            echo_stamp "VPN gateway is now reachable."
        fi
    fi

    sleep 2s
done
