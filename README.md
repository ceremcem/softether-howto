# Linux Client

> Based on https://www.cactusvpn.com/tutorials/how-to-set-up-softether-vpn-client-on-linux/

## Download and Compile SoftEther client

Get [Linux x64 client](http://www.softether-download.com/files/softether/v4.28-9669-beta-2018.09.11-tree/Linux/SoftEther_VPN_Client/64bit_-_Intel_x64_or_AMD64/) or an appropriate one from [here](http://www.softether-download.com/files/softether/).

```
apt -y install build-essential  # if needed
wget $THE_LINK
tar xvf softether*.tar.gz
cd vpnclient
make
```

## Configure the VPN Client

It is sufficient to run the provided script to connect to your VPN:

```sh
./connect-to-vpn.sh
```

> If you manually make your configuration, see the [HOWTO](./HOWTO.md).
