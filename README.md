# Linux Client Setup

## Download and Compile SoftEther client

Get [Linux x64 client](http://www.softether-download.com/files/softether/v4.28-9669-beta-2018.09.11-tree/Linux/SoftEther_VPN_Client/64bit_-_Intel_x64_or_AMD64/) or an appropriate one from [here](http://www.softether-download.com/files/softether/).

```
sudo apt-get install -y build-essential
wget $THE_LINK
tar xvf softether*.tar.gz
cd vpnclient
make
```

### Build from source 

If you want to build from source, use the following (based on [this](https://github.com/SoftEtherVPN/SoftEtherVPN/issues/301#issuecomment-320073384)):

```
sudo apt update 
sudo apt-get install -y zlib1g-dev libncurses5-dev libssl-dev build-essential libreadline-dev git 
required_cmake="3.7"
available_cmake=$(sudo apt-cache policy cmake | grep Candidate | cut -d: -f2 | sed -rn 's/\s*([0-9]+\.[0-9]+).*/\1/p') 
if dpkg --compare-versions $available_cmake ge $required_cmake; then
    echo "Installing cmake ($available_cmake) from repository..."
    sudo apt-get install -y cmake
else
    echo "Error: Available cmake version ($available_cmake) is not sufficient."
    echo "You are supposed to compile cmake>$required_cmake from source on your own."
    read -p "Press enter to continue"
fi
sudo ldconfig
git clone --depth=1 https://github.com/SoftEtherVPN/SoftEtherVPN.git
cd SoftEtherVPN/src/Mayaqua
mv Network.c Network.c.orig
cat Network.c.orig | sed ‘s!SSLv3_method!SSLv23_client_method!g’ > Network.c
cd ../..
./configure
make
```

If `cmake<3.7` then compile `cmake` from source: 
```
wget https://github.com/Kitware/CMake/releases/download/v3.14.5/cmake-3.14.5.tar.gz
tar -xvzf cmake*.gz
cd cmake*
sudo ./bootstrap
sudo make
sudo checkinstall -D make install  # or `sudo make install`
...
```
Tested on 

* Raspberry Pi


## Configure the VPN Client

> Assuming this repo and `vpnclient` folder (above) are placed side by side, in the same folder. 

It is sufficient to run the provided script to connect to your VPN:

```sh
cp sample.config my-account.config
# edit my-account.config accordingly
./connect-to-vpn.sh my-account.config
```

> If you want to make your configuration manually, see the [HOWTO](./HOWTO.md).

