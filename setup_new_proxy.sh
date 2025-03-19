#!/usr/bin/env bash
set -x

echo "setting up"
WORKDIR="${1:-$(mktemp -d)}"
echo "setting up ${WORKDIR}"

pushd "$WORKDIR"

apt update -y && apt install -y apt-transport-https curl gnupg make gcc < /dev/null

# add diladele apt key
wget -qO - https://packages.diladele.com/diladele_pub.asc | apt-key add -

# add new repo
tee /etc/apt/sources.list.d/squid413-ubuntu20.diladele.com.list <<EOF
deb https://squid413-ubuntu20.diladele.com/ubuntu/ focal main
EOF

# and install
apt-get update && apt-get install -y squid-common squid-openssl squidclient libecap3 libecap3-dev < /dev/null

mkdir -p /var/lib/squid

/usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB || true

chown -R proxy:proxy /var/lib/squid

# Name of the VM on which Squid is hosted
HOST="10.42.3.5"

CACERT="<<CACERT>>"
CAKEY="<<CAKEY>>"

echo "$CAKEY" | base64 -d > squidk.pem
echo "$CACERT" | base64 -d > squidc.pem

chown proxy:proxy squidc.pem
chown proxy:proxy squidk.pem
chmod 400 squidc.pem 
chmod 400 squidk.pem
cp squidc.pem /etc/squid/squidc.pem
cp squidk.pem /etc/squid/squidk.pem
cp squidc.pem /usr/local/share/ca-certificates/squidc.crt
update-ca-certificates 

sed -i 's~http_access deny all~http_access allow all~' /etc/squid/squid.conf
sed -i "s~http_port 3128~http_port $HOST:3128\nhttps_port $HOST:3129 tls-cert=/etc/squid/squidc.pem tls-key=/etc/squid/squidk.pem~" /etc/squid/squid.conf

systemctl restart squid
systemctl status squid

curl -fsSl -o /dev/null -w '%{http_code}\n' -x http://${HOST}:3128/ -I http://www.google.com
curl -fsSl -o /dev/null -w '%{http_code}\n' -x http://${HOST}:3128/ -I https://www.google.com
curl -fsSl -o /dev/null -w '%{http_code}\n' -x https://${HOST}:3129/ -I http://www.google.com
curl -fsSl -o /dev/null -w '%{http_code}\n' -x https://${HOST}:3129/ -I https://www.google.com
