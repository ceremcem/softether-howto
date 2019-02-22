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

* SoftEther server IP
* SoftEther server port
* Your username and password
* The virtual hub name to connect to
* The VPN gateway IP


### 1. Start the SoftEther VPN client:

```
sudo ./vpnclient start
```

If you see this message: “The SoftEther VPN Client service has been started.” then the SoftEther VPN client has successfully started.


### 2. Check the SoftEther VPN client installation:

1. `./vpncmd`
2. Select “3” to enter “Use of VPN Tools (certificate creation and Network Traffic Speed Test Tool)”.
3. Type `Check`
4. If all the checks are passed, you can go to the next step.
5. Press “Ctrl” + “C” or “Ctrl” + “D” to exit.

### 3. Set up SoftEther VPN client account

Start configuration with:

```
./vpncmd
```

1. Select “2. Management of VPN Client”.
2. Do not enter any addresses at “Hostname of IP Address of Destination” and press “Enter” to connect to the localhost.

    > If you have error: 
    > * Stop the VPN client with `sudo ./vpnclient stop`
    > * Edit the configuration file (`vpn_client.config`) and set `bool AllowRemoteConfig true`. 
    > * Start the VPN client with `sudo ./vpnclient start`
  
3. Create a virtual interface to connect to the VPN server. In the SoftEther VPN configuration type:

       NicCreate vpn_se

4. Create an account that will use this interface for the VPN connection. Run this command in the terminal:

       AccountCreate hithere
    
5. Set up VPN account with your details.

       “Destination Virtual Hub Name”: {Your hub name}
       “Destination VPN server Host Name and Port Number”: {VPN IP address}:{SoftEther VPN Port}
       “Connecting User Name”: {your VPN username}
       “Used Virtual Network Adapter Name”: vpn_se

    > If you get the “The command completed successfully.” message, it means that the account creation was successfully finished.

6. Set up a password:

       AccountPassword hithere
       
     > and enter your VPN password for “Password” and “Confirm input”.

7. Test the connection to the VPN server:

       AccountList

    > If you see `Status: Connected`, you can go to the next step.
    
    
## Connecting to VPN

1. Check if the IP forward is enabled on your system:


      cat /proc/sys/net/ipv4/ip_forward
      
   > If you get “1” you can skip this step and go to the “Obtain an IP address from the VPN server” step.
   > If not, type 
   > ```
   > echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
   > ```
   
   
2. Obtain an IP address from the VPN server:

    1. See you have the `vpn_vpn_se` interface:

      ```
      $ ifconfig
      ...
      vpn_vpn_se: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet6 fe80::5cb9:78ff:fe05:9832  prefixlen 64  scopeid 0x20<link>
            ether 5e:b9:78:05:98:32  txqueuelen 1000  (Ethernet)
            RX packets 98620  bytes 66064239 (63.0 MiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 57980  bytes 5530797 (5.2 MiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
      ```

    2. To get an IP address from the VPN server:

        ```
        sudo dhclient vpn_vpn_se
        ```

        > You should get an `ifconfig` output similar to this:
        > ```
        > vpn_vpn_se: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        >   inet 192.168.30.11  netmask 255.255.255.0  broadcast 192.168.30.255
        >   inet6 fe80::5cb9:78ff:fe05:9832  prefixlen 64  scopeid 0x20<link>
        >   ether 5e:b9:78:05:98:32  txqueuelen 1000  (Ethernet)
        >   RX packets 98620  bytes 66064239 (63.0 MiB)
        >   RX errors 0  dropped 0  overruns 0  frame 0
        >   TX packets 57980  bytes 5530797 (5.2 MiB)
        >   TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
        > ```

      
    3. Add a route to the VPN server’s IP address via your old default route. In my specific case:

        ```
        sudo ip route add 93.115.92.240/32 via 192.168.0.1
        sudo route add default 192.168.30.1
        ```

        Where:

        * `93.115.92.240` is the `{VPN IP address}`
        * `192.168.0.1` is the IP address of current gateway
        * `192.168.30.1` is the IP of SoftEther VPN gateway address


    4. Delete the old default route:

            sudo ip route del default via 192.168.0.1

    5. Check your internet connection:

            ping 8.8.8.8 -c4

    6. Check your public IP (which should be the same as `{VPN IP address}`): 

            wget -qO- http://ipecho.net/plain ; echo


        > If you see the VPN server’s IP, everything was set up correctly and your 
        > Linux is connected to the VPN via SoftEther VPN client.
        > 
        > If the ping to the “8.8.8.8” is OK but you can not retrieve anything else by
        > public hostname, add Google DNS (or any Public DNS server) to your “/etc/resolv.conf” file:
        > 
        > ```
        > sudo echo nameserver 8.8.8.8 >> /etc/resolv.conf
        > ```
      
### Disconnecting from VPN

When you are done with VPN connection, you should perform the followings to properly disconnect from VPN:

1. Delete the VPN route:

        sudo ip route del 93.115.92.240/32            # Where the IP is {VPN IP address}
  
2. Add a default route via your local gateway

        sudo ip route add default via 192.168.0.1     # Where the IP is your local gateway IP address
  
3. Optionally: Stop the VPN client:

        sudo ./vpnclient stop








