#!/bin/bash
#
# This script is executed inside the maas-region-controller container
# once it is setup by setup-dev-env.sh
#

# stop execution/exit on error
set -e
sudo update-ca-certificates

# add the CN to the /etc/hosts
hn=$(openssl x509 -noout -subject -in /usr/local/share/ca-certificates/$base_filename -nameopt multiline | grep commonName | awk '{ print $3 }')
echo $MAAS_MANAGEMENT_IP_RANGE $hn | sudo tee --append /etc/hosts
