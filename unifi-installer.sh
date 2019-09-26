#!/bin/bash
while getopts e:d: option
do
case "${option}"
in
e) EMAIL=${OPTARG};;
d) HOSTNAMEVAR=${OPTARG};;

esac
done
echo $EMAIL;
echo $HOSTNAMEVAR;

apt-get update && apt-get upgrade -y

echo "Installing swap"
fallocate -l 1G /swapfile
chmod 600 /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
echo "vm.swappiness=10" >> /etc/sysctl.conf

echo "Installing support tools"
apt-get install apt-transport-https -y
apt-get install ncdu -y
apt-get install htop -y

echo "Setting hostname"
hostname $HOSTNAMEVAR
hostnamectl set-hostname $HOSTNAMEVAR

echo "Installing UniFi"
wget -O /etc/apt/trusted.gpg.d/unifi-repo.gpg https://dl.ubnt.com/unifi/unifi-repo.gpg 
echo 'deb http://www.ubnt.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list
apt-get update && apt-get install unifi -y

echo "Installing NGINX"
apt-get install nginx-light -y

echo "Installing Let's Encrypt"
echo "deb http://ftp.debian.org/debian stretch-backports main" | tee -a /etc/apt/sources.list
apt-get update -y
apt-get install python-certbot-nginx -t stretch-backports -y
certbot --nginx --email $EMAIL --agree-tos --no-eff-email --domain $HOSTNAMEVAR --no-redirect
wget -O /root/unifi-lets-encrypt-ssl-importer.sh https://raw.githubusercontent.com/HostiFi/unifi-lets-encrypt-ssl-importer/master/unifi-lets-encrypt-ssl-importer.sh
chmod +x /root/unifi-lets-encrypt-ssl-importer.sh
/root/unifi-lets-encrypt-ssl-importer.sh -d $HOSTNAMEVAR

echo "Creating Let's Encrypt cron"
crontab -l > /root/letsencryptcron
echo "0 23 * * * /bin/bash /root/unifi-lets-encrypt-ssl-importer.sh -d $HOSTNAMEVAR" >> /root/letsencryptcron
crontab /root/letsencryptcron
rm /root/letsencryptcron

echo "Creating firewall rules"
iptables -t nat -I PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8443
iptables -A INPUT -i ens3 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8080 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p udp --dport 3478 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 8843 -j ACCEPT
iptables -A INPUT -j DROP
iptables -A OUTPUT -o ens3 -j ACCEPT

echo "Saving firewall rules"
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get install iptables-persistent netfilter-persistent -y

netfilter-persistent save

echo "Configuring NGINX to forward HTTP to HTTPS"
echo "server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}" > /etc/nginx/sites-available/redirect
ln -s /etc/nginx/sites-available/redirect /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

echo "Restarting services"
systemctl restart nginx
systemctl restart unifi

echo "Done!"
