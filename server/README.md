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

# Initial setup

* Change server admin password: 

      vpncmd /server localhost ServerPasswordSet

# Get up and running 

> Hint: Type "Something<ENTER>" to get related commands.

0. Connect to the control shell:

       vpncmd /server localhost

1. Create a `Hub`:

       HubCreate foo
       # set your hub password 

2. Use this hub: 

       Hub foo

3. Create a user:
    
       UserCreate bar

4. Set a password

       UserPasswordSet bar
 
5. Enable SecureNAT

       SecureNatEnable

# Forward physical machine port to vpn client port

See ["How to forward server port from physical machine to VPN client in SoftEther?
"](https://superuser.com/q/1408862/187576)


