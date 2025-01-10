#!/bin/bash
#
# This script is executed inside the maas-region-controller container
# once it is setup by setup-dev-env.sh
#

# stop execution/exit on error
set -e

container_ip=$(hostname -I | cut -d' ' -f1)
gateway_ip=$(hostname -I | cut -d' ' -f1)
control_network_prefix=${MAAS_CONTROL_IP_RANGE%.*}
kvm_network_prefix=${MAAS_MANAGEMENT_IP_RANGE%.*}
ipv6_network_prefix=${MAAS_IPV6_IP_RANGE%:*}
dual_stack_ipv4_prefix=${MAAS_DUAL_STACK_IPV4_RANGE%.*}
dual_stack_ipv6_prefix=${MAAS_DUAL_STACK_IPV6_RANGE%:*}

echo "${container_ip} ${gateway_ip} ${control_network_prefix} ${kvm_network_prefix} ${ipv6_network_prefix} ${dual_stack_ipv4_prefix} ${dual_stack_ipv6_prefix}"

echo
echo "######################################"
echo "Installing make and MAAS dependencies."
sudo apt-get install make
cd /work
make install-dependencies

echo
echo "##########################################################"
echo "Setting up the secondary interface (no dhcp ones) to talk home"
sudo tee /etc/netplan/99-maas-kvm-net.yaml <<EOF
network:
    version: 2
    ethernets:
        eth1:
            addresses:
                - ${kvm_network_prefix}.2/24
        eth2:
            addresses:
                - ${ipv6_network_prefix}:2/64
        eth3:
            addresses:
                - ${dual_stack_ipv4_prefix}.2/24
                - ${dual_stack_ipv6_prefix}:2/64
EOF
sudo netplan apply

echo
echo "############################################"
echo "Disabling postgres, nginx and dhcp services."
sudo systemctl stop named postgresql nginx isc-dhcp-server
sudo systemctl disable named postgresql nginx isc-dhcp-server

echo
echo "#################################"
echo "Installing the MAAS test database"
sudo snap install maas-test-db --channel=latest/edge

echo
echo "#######################"
echo "Unpacking the snap tree"
sudo snap try dev-snap/tree

echo
echo "##########################"
echo "Connecting snap interfaces"
./utilities/connect-snap-interfaces

echo
echo "####################################"
echo "Installing and running the MAAS snap"
make
make snap-tree-sync
sudo snap restart maas

echo
echo "#######################"
echo "Generating offline docs"
make doc

echo
echo "#####################"
echo "Starting the database"
sudo maas init region+rack --maas-url="http://${container_ip}:5240/MAAS" --database-uri maas-test-db:///

echo
echo "##########################"
echo "Creating a MAAS admin user"
sudo maas createadmin --username maas --password maas --email maas@example.com

echo
echo "###########################"
echo "Login using admin profile"
declare -i maas_up=1
while [ $maas_up -ne 0 ]; do
  maas login admin "http://${container_ip}:5240/MAAS/api/2.0/" $(sudo maas apikey --username=maas);
  maas_up=$?
  if [ $maas_up -ne 0 ]; then
    echo "Retrying in 5 seconds..."
    sleep 5
  fi
done

echo
echo "###############################"
echo "Starting DHCP on second network"
rack_controllers=$(maas admin rack-controllers read)
target_rack_controller=$(echo $rack_controllers | jq --raw-output .[].system_id)
target_fabric_id=$(echo $rack_controllers | jq '.[].interface_set[].links[] | select(.subnet.name | startswith('\"$kvm_network_prefix.\"')) | .subnet.vlan.fabric_id')
maas admin subnet update ${kvm_network_prefix}.0/24 gateway_ip=${kvm_network_prefix}.1
export ip_range=$(maas admin ipranges create type=dynamic start_ip=${kvm_network_prefix}.99 end_ip=${kvm_network_prefix}.254 comment='To enable dhcp')
maas admin vlan update $target_fabric_id untagged dhcp_on=True primary_rack=$target_rack_controller

echo
echo "#############################"
echo "Adding your hosts lxd to MAAS"
maas admin vm-hosts create type=lxd power_address=${control_network_prefix}.1 project=maas name=maas-host

echo
echo "#################################################################"
echo "We are done! You should have a running MAAS installation!"
echo
echo "  please go to http://${container_ip}:5240 and finish the setup"
echo "   username: maas"
echo "   password: maas"
echo
echo "To complete the setup point your browser to"
echo "  http://${container_ip}:5240/MAAS/r/kvm/lxd"
echo "and do to maas-host -> KVM host settings -> Download certificate."
echo "Install the certificate to your local lxd with:"
echo "  lxc config trust add <path/to/maas-host@...>"
echo "Go back to your browser and click 'Refresh host'"
echo
echo "Have fun developing MAAS"
echo
echo
