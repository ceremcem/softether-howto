# Installing Server on Debian 

```
sudo -s
apt-get update
apt-get install build-essential libreadline-dev libssl-dev libncurses-dev zlib1g-dev git cmake
git clone --recursive https://github.com/SoftEtherVPN/SoftEtherVPN.git

cd SoftEtherVPN
./configure
make -C tmp
cd ./tmp
make install
vpnserver start
```

### Add the /etc/init.d/ script 

```
cp ./vpnserver /etc/init.d/vpnserver
chmod +x /etc/init.d/vpnserver
update-rc.d vpnserver defaults
```


# Initial Setup 

See [HOWTO](./HOWTO.md).
