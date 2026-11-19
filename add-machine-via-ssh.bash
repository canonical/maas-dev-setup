#!/bin/bash
#
# This script is executed inside the dev container
# by setup-dev-env.sh. It enlists one (empty, stopped) LXD VM from the
# host as a MAAS machine with the lxd power driver.
#
# Expected environment:
#   MACHINE_NAME   hostname in MAAS and LXD instance name
#   MACHINE_MAC    MAC address of the VM's PXE interface (eth0)
#   LXD_ADDRESS    address of the host's LXD API (port defaults to 8443)
#   LXD_PROJECT    LXD project the VM lives in
#   LXD_CERT/KEY   paths to the client certificate/key trusted by the host's LXD
#

set -e

arch="$(dpkg --print-architecture)/generic"

echo
echo "######################################################"
echo "Checking that LXD at ${LXD_ADDRESS} trusts the power certificate"
auth=$(curl -sk --cert "${LXD_CERT}" --key "${LXD_KEY}" "https://${LXD_ADDRESS}:8443/1.0" | jq -r .metadata.auth)
if [ "${auth}" != "trusted" ]; then
  echo "ERROR: LXD at ${LXD_ADDRESS} reports auth='${auth}' for ${LXD_CERT} (expected 'trusted')" >&2
  exit 1
fi

echo
echo "######################################################"
echo "Adding ${MACHINE_NAME} (${MACHINE_MAC}) to MAAS"
if [ "$(maas admin machines read mac_address="${MACHINE_MAC}" | jq length)" -ne 0 ]; then
  echo "A machine with MAC ${MACHINE_MAC} already exists in MAAS, skipping"
  exit 0
fi

maas admin machines create \
  hostname="${MACHINE_NAME}" \
  architecture="${arch}" \
  mac_addresses="${MACHINE_MAC}" \
  power_type=lxd \
  power_parameters_power_address="${LXD_ADDRESS}" \
  power_parameters_project="${LXD_PROJECT}" \
  power_parameters_instance_name="${MACHINE_NAME}" \
  power_parameters_certificate="$(cat "${LXD_CERT}")" \
  power_parameters_key="$(cat "${LXD_KEY}")" \
  | jq -r '"..created \(.hostname) (\(.system_id)), status: \(.status_name)"'
