#!/usr/bin/env bash
set -x

export GROUP="lilypan-rg"
export LOCATION="eastus"

set -uo pipefail

HOST="10.42.3.5"

CONFIG="
[req]
distinguished_name=dn
[ dn ]
[ ext ]
basicConstraints=CA:TRUE,pathlen:0
"

openssl req -config <(echo "$CONFIG") -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout squidk.pem -out squidc.pem -subj "/CN=${HOST}" -addext "subjectAltName=IP:${HOST},DNS:cli-proxy-vm" -addext "basicConstraints=critical,CA:TRUE,pathlen:0" -addext "keyUsage=critical,keyCertSign,cRLSign,keyEncipherment,encipherOnly,decipherOnly,digitalSignature,nonRepudiation" -addext "extendedKeyUsage=clientAuth,serverAuth"

sed "s/<<CACERT>>/$(cat squidc.pem | base64 -w 0)/g" setup_new_proxy.sh | sponge setup_out.sh
sed "s/<<CAKEY>>/$(cat squidk.pem | base64 -w 0)/" setup_out.sh | sponge setup_out.sh
jq --arg cert "$(cat squidc.pem | base64 -w 0)" '.trustedCa=$cert' newhttpproxyconfig.json | sponge newhttpproxyconfig.json


# name below MUST match the name used in testcerts for httpproxyconfig.json.
# otherwise the VM will not present a cert with correct hostname
# else, change the cert to have the correct hostname (harder)
az vm create \
    --resource-group=${GROUP} \
    --name=cli-proxy-vm2 \
    --image Canonical:0001-com-ubuntu-server-focal:20_04-lts:latest \
    --ssh-key-values /home/lpan/.ssh/id_rsa.pub \
    --public-ip-address "" \
    --custom-data ./setup_out.sh \
    --vnet-name=${GROUP}-vnet \
    --subnet proxy-subnet \
    --private-ip-address $HOST
