# Linux Client

> Based on https://www.cactusvpn.com/tutorials/how-to-set-up-softether-vpn-client-on-linux/

## Install SoftEther VPN Client

### 1. Download SoftEther client

Get [Linux x64 client](http://www.softether-download.com/files/softether/v4.28-9669-beta-2018.09.11-tree/Linux/SoftEther_VPN_Client/64bit_-_Intel_x64_or_AMD64/) or an appropriate one from [here](http://www.softether-download.com/files/softether/).

### 2. Decompress SofEther VPN client

```
tar xvf softether*.tar.gz
```

### 3. Make sure your system have all the needed tools for SoftEther compilation.

```
apt -y install build-essential
```

### 4. Compile SoftEther

```
cd vpnclient
make
```

### 5. Accept the SoftEther License

SoftEther will ask you to read and agree its License Agreement. Select 1 to read the agreement, again to confirm you have read it and finally to agree to the License Agreement.

SoftEther is now compiled and it’s an executable file (vpnclient and vpncmd). If the process fails, check if you have all of the requirement packages installed.



## Configure the VPN Client 

> Assuming you are still in `vpnclient/` directory

Requirements:

| name                                  | example value     |  where to get | 
| ----                                  | ----              | ---           | 
| SoftEther server IP                   | 111.111.111.111   | Ask your VPN provider |
| SoftEther server port                 | 443               | Ask your VPN provider | 
| Your VPN username                     | myuser            | Ask your VPN provider |
| Your VPN password                     | 1234567*          | Ask your VPN provider | 
| The virtual hub name to connect to    | VPN               | Ask your VPN provider |
| The VPN gateway IP                    | 192.168.30.1      | Ask your VPN provider |
| Your local gateway IP                 | 192.168.1.1       | `ip route \| grep default` |     


### 1. Start the SoftEther VPN client:

```
sudo ./vpnclient start
```

If you see this message: “The SoftEther VPN Client service has been started.” then the SoftEther VPN client has successfully started.


### 2. Check the SoftEther VPN client installation:

```
./vpncmd localhost /tools /cmd check
```

If all the checks are passed, you can go to the next step.


### 3. Set up SoftEther VPN client and account

> If you get "does not allow remote administration connections" error, see [this](https://github.com/SoftEtherVPN/SoftEtherVPN/issues/209#issuecomment-426397152)

1. Create NIC:

       ./vpncmd localhost /client /cmd NicCreate aaa_se
       
     > You should be able to see a NIC created with name `vpn_aaa_se`: 
     > ```
     > ifconfig vpn_aaa_se
     > ```

2. Create an account:

       ./vpncmd localhost /client /cmd AccountCreate heyyou /SERVER:111.111.111.111:443 /HUB:VPN /USERNAME:myuser /NICNAME:aaa_se
    
3. Set up a password for your account:

       ./vpncmd localhost /client /cmd AccountPassword heyyou /PASSWORD:1234567* /TYPE:radius
           
## Connecting to VPN

1. Connect to VPN with your account:

        ./vpncmd localhost /client /cmd AccountConnect heyyou

2. Test the connection to the VPN server:

        ./vpncmd localhost /client /cmd AccountList

   If you see `Status: Connected`, you can go to the next step.


### Set up the routing table 

1. Enable IP forward on your system:

        echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward   
   
4. Obtain an IP address from the VPN server:

    1. To get an IP address from the VPN server:

        ```
        sudo dhclient vpn_aaa_se
        ```

        > You should get an output similar to this:
        > ```
        > $ ifconfig vpn_aaa_se | grep inet | grep netmask
        > inet 192.168.30.10  netmask 255.255.255.0  broadcast 192.168.30.255
        > ```

      
    2. Add a route to the VPN server’s IP address via your old default route:

        ```
        sudo ip route add 111.111.111.111/32 via 192.168.1.1
        sudo route add default 192.168.30.1
        ```

    3. Delete the old default route:

            sudo ip route del default via 192.168.1.1

    4. Check your internet connection:

            ping 8.8.8.8 -c10

    5. Check your public IP (which should be `111.111.111.111`): 

            wget -qO- http://ipecho.net/plain ; echo


        > If you see the VPN server’s IP, everything was set up correctly and your 
        > Linux is connected to the VPN via SoftEther VPN client.
        > 
        > If the ping to the `8.8.8.8` is OK but you can not retrieve anything else by
        > public hostname, add Google DNS (or any Public DNS server) to your `/etc/resolv.conf` file:
        > 
        > ```
        > echo nameserver 8.8.8.8 | sudo tee /etc/resolv.conf
        > ```
      
### Disconnecting from VPN

When you are done with VPN connection, you should perform the followings to properly disconnect from VPN:

1. Delete the VPN route:

        sudo ip route del 111.111.111.111/32
        sudo route del default
  
2. Add a default route via your local gateway

        sudo ip route add default via 192.168.1.1
  
3. Optionally: Disconnect and stop the VPN client:

       ./vpncmd localhost /client /cmd AccountDisconnect heyyou
       sudo ./vpnclient stop








