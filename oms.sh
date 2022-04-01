#!/usr/bin/env bash
set -x

NEWGRP="ace-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 8 | head -n 1)"
export GROUP="${GROUP:=$NEWGRP}"
export LOCATION="eastus"

set -uo pipefail

HOST="10.42.3.4"

CONFIG="
[req]
distinguished_name=dn
[ dn ]
[ ext ]
basicConstraints=CA:TRUE,pathlen:0
"

openssl req -config <(echo "$CONFIG") -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout squidk.pem -out squidc.pem -subj "/CN=${HOST}" -addext "subjectAltName=IP:${HOST},DNS:cli-proxy-vm" -addext "basicConstraints=critical,CA:TRUE,pathlen:0" -addext "keyUsage=critical,keyCertSign,cRLSign,keyEncipherment,encipherOnly,decipherOnly,digitalSignature,nonRepudiation" -addext "extendedKeyUsage=clientAuth,serverAuth"

sed "s/<<CACERT>>/$(cat squidc.pem | base64 -w 0)/g" setup_proxy.sh | sponge setup_out.sh
sed "s/<<CAKEY>>/$(cat squidk.pem | base64 -w 0)/" setup_out.sh | sponge setup_out.sh
jq --arg cert "$(cat squidc.pem | base64 -w 0)" '.trustedCa=$cert' httpproxyconfig.json | sponge httpproxyconfig.json

az group create -g "${GROUP}" -l "${LOCATION}" --tags "aleldeib=true"

az network vnet create \
    --resource-group=${GROUP} \
    --name=${GROUP}-vnet \
    --address-prefixes 10.42.0.0/16 \
    --subnet-name aks-subnet \
    --subnet-prefix 10.42.1.0/24

az network vnet subnet create \
    --resource-group=${GROUP} \
    --vnet-name=${GROUP}-vnet \
    --name proxy-subnet \
    --address-prefix 10.42.3.0/24

vnet_subnet_id=$(az network vnet subnet show \
    --resource-group=${GROUP} \
    --vnet-name=${GROUP}-vnet \
    --name aks-subnet -o json | jq -r .id)

# name below MUST match the name used in testcerts for httpproxyconfig.json.
# otherwise the VM will not present a cert with correct hostname
# else, change the cert to have the correct hostname (harder)
az vm create \
    --resource-group=${GROUP} \
    --name=cli-proxy-vm \
    --image Canonical:0001-com-ubuntu-server-focal:20_04-lts:latest \
    --ssh-key-values @/home/azureuser/.ssh/id_rsa.pub \
    --public-ip-address "" \
    --custom-data ./setup_out.sh \
    --vnet-name=${GROUP}-vnet \
    --subnet proxy-subnet \
    --private-ip-address $HOST

az aks create --resource-group=$GROUP --name=$NEWGRP \
    --http-proxy-config=httpproxyconfig.json \
    --ssh-key-value @/home/azureuser/.ssh/id_rsa.pub \
    --enable-managed-identity \
    --yes --vnet-subnet-id ${vnet_subnet_id} \
    --enable-addons monitoring,azure-policy