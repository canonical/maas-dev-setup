#!/bin/sh
#
# This script sets up a development environment for MAAS
#

# set -e might be too strict for some tasks
#   e.g cloning in an existing directory usually works
set -e

# source config and setup variables
. ./config.sh

# Validate MAAS_INSTANCE: max 5 digits, required for kernel bridge name limit (15 chars).
if [ ${#MAAS_INSTANCE} -gt 5 ]; then
  echo "ERROR: MAAS_INSTANCE must be at most 5 digits (got: '${MAAS_INSTANCE}')."
  echo "  Kernel bridge names are limited to 15 chars; 'maas-ctrl-' occupies 10 of them."
  exit 1
fi

# get absolute path for lxd
maas_src=$(readlink -f ${MAAS_SRC})
# see https://stackoverflow.com/questions/29832037/how-to-get-script-directory-in-posix-sh
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

control_network_prefix=${MAAS_CONTROL_IP_RANGE%.*}
kvm_network_prefix=${MAAS_MANAGEMENT_IP_RANGE%.*}

run_it_arg="--ok"
run_it=0
skip_ufw=0
skip_dep=0
skip_lxi=0
skip_lxd=0
skip_lxn=0
skip_co=0
skip_snap=0
crt_file=""

show_help() {
  echo "Description:"
  echo "  This script sets up a complete dev environment for MAAS."
  echo ""
  echo "  !Attention! This will install packages to your system and"
  echo "    setup profiles, networks and containers for MAAS in LXD"
  echo ""
  echo "  The script does:"
  echo "    * DISABLE YOUR UFW FIREWALL (to make sure lxd connections work)"
  echo "    * install git, make, lxd, snapcraft"
  echo "    * clone the source code and"
  echo "      (if configured) add a branch for your launchpad account"
  echo "    * setup bridges so that MAAS can reach your network"
  echo "    * setup LXD so that MAAS can search through your local network"
  echo "    * connect your local LXD to the MAAS development container so that"
  echo "      MAAS can provision virtual machines"
  echo ""
  echo "Usage:"
  echo "  $0"
  echo "  $0 ${run_it_arg}"
  echo ""
  echo "Flags:"
  echo "  -h --help         show this help"
  echo "  ${run_it_arg}              start the setup"
  echo "  -su --skip-ufw    skip disabling UFW"
  echo "  -sd --skip-dep    skip installing dependencies to your local system"
  echo "  -si --skip-lxi    skip initializing LXD (lxd auto init)"
  echo "  -sn --skip-lxn    skip setting up LXD profiles and networks"
  echo "  -sl --skip-lxd    skip starting the LXD container"
  echo "  -sc --skip-checkout skip checking out the code"
  echo "  -ss --skip-snap   skip building the snap tree"
  echo "  -c  --ca-crt      add the given .crt (PEM format) file to the trusted CAs in the lxd container" 
  echo ""
  echo "Note:"
  echo "  If you installed maas before you likely want to run: ./$0 -su -sd -sv --ok"
  echo ""
}

disable_ufw() {
  if command -v ufw > /dev/null; then
    echo "Disabling UFW firewall..."
    echo "#########################"
    sudo ufw disable
    echo "..done"
  else
    echo "#################################"
    echo "ufw command not found, continuing"
  fi
  echo
}

install_dependencies() {
  # install MAAS dependencies
  echo "##########################"
  echo "Installing dependencies..."
  sudo snap install lxd
  sudo snap install snapcraft --classic
  sudo apt-get install git make
  echo "..done"
  echo
}

init_lxd() {
  echo "###################"
  echo "Initializing LXD..."
  lxd init --auto
  echo "..done"
  echo
}

setup_code() {
  echo "################################"
  echo "Cloning code into ${maas_src}..."
  mkdir -p ${maas_src} && cd ${maas_src}
  git clone --origin upstream https://git.launchpad.net/maas . --recurse-submodules
  echo "..done"
  if [ ${MAAS_LAUNCHPAD_ID} != "" ]; then
    echo "Adding your origin remote git+ssh://${MAAS_LAUNCHPAD_ID}@git.launchpad.net/~${MAAS_LAUNCHPAD_ID}/maas"
    git remote add origin git+ssh://${MAAS_LAUNCHPAD_ID}@git.launchpad.net/~${MAAS_LAUNCHPAD_ID}/maas
  fi
  echo "..done"
  echo
}

make_snap_tree() {
  echo "########################"
  echo "Setting up the snap tree"
  cd ${maas_src}
  make snap-tree
  echo "..done"
  echo
}

setup_lxd() {
  echo "#######################"
  echo "Setting up LXD networks"
  cd ${script_dir}

  if lxc network show ${MAAS_CTRL_NETWORK} >/dev/null 2>&1; then
    echo "Network ${MAAS_CTRL_NETWORK} already exists, skipping."
  else
    lxc network create ${MAAS_CTRL_NETWORK}
    cat << __EOF | lxc network edit ${MAAS_CTRL_NETWORK}
config:
  dns.domain: ${MAAS_CTRL_NETWORK}
  ipv4.address: ${MAAS_CONTROL_IP_RANGE}/24
  ipv4.dhcp: "true"
  ipv4.dhcp.ranges: ${control_network_prefix}.16-${control_network_prefix}.31
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: ${MAAS_CTRL_NETWORK}
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  fi

  if lxc network show ${MAAS_KVM_NETWORK} >/dev/null 2>&1; then
    echo "Network ${MAAS_KVM_NETWORK} already exists, skipping."
  else
    lxc network create ${MAAS_KVM_NETWORK}
    cat << __EOF | lxc network edit ${MAAS_KVM_NETWORK}
config:
  ipv4.address: ${MAAS_MANAGEMENT_IP_RANGE}/24
  ipv4.dhcp: "false"
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: ${MAAS_KVM_NETWORK}
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  fi

  if lxc network show ${MAAS_IPV6_NETWORK} >/dev/null 2>&1; then
    echo "Network ${MAAS_IPV6_NETWORK} already exists, skipping."
  else
    lxc network create ${MAAS_IPV6_NETWORK}
    cat << __EOF | lxc network edit ${MAAS_IPV6_NETWORK}
config:
  ipv4.address: none
  ipv6.address: ${MAAS_IPV6_IP_RANGE}/64
  ipv6.dhcp: "false"
  ipv6.nat: "true"
description: "An IPv6 only network"
name: ${MAAS_IPV6_NETWORK}
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  fi

  if lxc network show ${MAAS_DUAL_STACK_NETWORK} >/dev/null 2>&1; then
    echo "Network ${MAAS_DUAL_STACK_NETWORK} already exists, skipping."
  else
    lxc network create ${MAAS_DUAL_STACK_NETWORK}
    cat << __EOF | lxc network edit ${MAAS_DUAL_STACK_NETWORK}
config:
  ipv4.address: ${MAAS_DUAL_STACK_IPV4_RANGE}/24
  ipv4.nat: "true"
  ipv4.dhcp: "false"
  ipv6.address: ${MAAS_DUAL_STACK_IPV6_RANGE}/64
  ipv6.nat: "true"
  ipv6.dhcp: "false"
description: "A network for both IPv4 and IPv6"
name: ${MAAS_DUAL_STACK_NETWORK}
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  fi
  echo "..done"
  echo

  echo "#######################################"
  echo "Checking LXD HTTPS address configuration"
  current_https=$(lxc config get core.https_address 2>/dev/null)
  if [ -z "${current_https}" ]; then
    echo "Setting LXD HTTPS address to [::]:8443"
    lxc config set core.https_address [::]:8443
  elif [ "${current_https}" = "[::]:8443" ]; then
    echo "LXD HTTPS address already set to [::]:8443, skipping."
  else
    echo "WARNING: LXD HTTPS address is '${current_https}', not changing."
    echo "  MAAS may not be able to reach the host LXD if this is not reachable."
  fi
  echo "..done"
  echo

  echo "#######################"
  echo "Setting up LXD profiles"
  if lxc profile show ${MAAS_CONTAINER_NAME} >/dev/null 2>&1; then
    echo "Profile ${MAAS_CONTAINER_NAME} already exists, skipping."
  else
    lxc profile create ${MAAS_CONTAINER_NAME}
    cat <<EOF | lxc profile edit ${MAAS_CONTAINER_NAME}
config:
    raw.idmap: |
        uid $(id -u) 1000
        gid $(id -g) 1000
    user.vendor-data: |
        #cloud-config
        packages:
        - git
        - build-essential
        - jq
        runcmd:
        - cat /dev/zero | ssh-keygen -q -N ""
        ssh_authorized_keys:
        - $(cat ${HOME}/.ssh/id_rsa.pub | cut -d' ' -f1-2)
description: Build environment for MAAS
devices:
    work:
        type: disk
        source: ${maas_src}
        path: /work
    eth0:
        type: nic
        name: eth0
        network: ${MAAS_CTRL_NETWORK}
    eth1:
        type: nic
        name: eth1
        network: ${MAAS_KVM_NETWORK}
    eth2:
        type: nic
        name: eth2
        network: ${MAAS_IPV6_NETWORK}
    eth3:
        type: nic
        name: eth3
        network: ${MAAS_DUAL_STACK_NETWORK}
EOF
  fi
  echo "..done"
  echo
}

start_container() {
  echo "##################################################################"
  echo "Setting up MAAS development container named ${MAAS_CONTAINER_NAME}"
  if lxc info ${MAAS_CONTAINER_NAME} >/dev/null 2>&1; then
    echo "Container ${MAAS_CONTAINER_NAME} already exists, skipping launch."
  else
    lxc launch ubuntu:${UBUNTU_VERSION} ${MAAS_CONTAINER_NAME} -p default -p ${MAAS_CONTAINER_NAME}
    echo "..waiting for container to be ready.."
    lxc exec ${MAAS_CONTAINER_NAME} -- cloud-init status --wait
  fi
  echo "..done"
  echo
}

configure_container() {
  cd ${script_dir}
  container_ip=$(lxc list -c4 --format csv ${MAAS_CONTAINER_NAME} | grep "${control_network_prefix}"| cut -d' ' -f1)
  echo "################################################################"
  echo "SSHing into ${MAAS_CONTAINER_NAME} (${container_ip}) development and setting it up"
  # could pass vars in there with ssh ubuntu@${container_ip} 'bash -s' < setup-region-via-ssh.sh var1 var2 ...
  ssh -o "StrictHostKeyChecking no" ubuntu@${container_ip}\
      MAAS_INSTANCE=${MAAS_INSTANCE}\
      MAAS_CONTROL_IP_RANGE=${MAAS_CONTROL_IP_RANGE}\
      MAAS_MANAGEMENT_IP_RANGE=${MAAS_MANAGEMENT_IP_RANGE}\
      MAAS_IPV6_IP_RANGE=${MAAS_IPV6_IP_RANGE}\
      MAAS_DUAL_STACK_IPV4_RANGE=${MAAS_DUAL_STACK_IPV4_RANGE}\
      MAAS_DUAL_STACK_IPV6_RANGE=${MAAS_DUAL_STACK_IPV6_RANGE}\
      bash -s < setup-region-via-ssh.bash
}

add_ca_crt(){
  cd ${script_dir}
  container_ip=$(lxc list -c4 --format csv ${MAAS_CONTAINER_NAME} | grep "${control_network_prefix}"| cut -d' ' -f1)
  echo "################################################################"
  if ! test -f $crt_file; then
    echo "ERROR: CA crt file does not exist."
    exit 1
  fi
  echo "Copying CA crt file into container and adding it as a trusted CA"
  base_filename=$(basename $crt_file)
  lxc file push $crt_file $MAAS_CONTAINER_NAME/usr/local/share/ca-certificates/$base_filename
  ssh -o "StrictHostKeyChecking no" ubuntu@${container_ip}\
      MAAS_INSTANCE=${MAAS_INSTANCE}\
      MAAS_CONTROL_IP_RANGE=${MAAS_CONTROL_IP_RANGE}\
      MAAS_MANAGEMENT_IP_RANGE=${MAAS_MANAGEMENT_IP_RANGE}\
      MAAS_IPV6_IP_RANGE=${MAAS_IPV6_IP_RANGE}\
      MAAS_DUAL_STACK_IPV4_RANGE=${MAAS_DUAL_STACK_IPV4_RANGE}\
      MAAS_DUAL_STACK_IPV6_RANGE=${MAAS_DUAL_STACK_IPV6_RANGE}\
      base_filename=${base_filename}\
      bash -s < add-ca-cert.bash $base_filename
}

run() {
  if [ ${skip_ufw} -ne 1 ]; then
    disable_ufw
  else
    echo "Skipping UFW setup"
    echo ""
  fi
  if [ ${skip_dep} -ne 1 ]; then
    install_dependencies
  else
    echo "Skipping local dependencies"
    echo ""
  fi
  if [ ${skip_lxi} -ne 1 ]; then
    init_lxd
  else
    echo "Skipping LXD init"
    echo ""
  fi
  if [ ${skip_lxn} -ne 1 ]; then
    setup_lxd
  else
    echo "Skipping LXD setup"
    echo ""
  fi
  if [ ${skip_co} -ne 1 ]; then
    setup_code
  else
    echo "Skipping code checkout"
    echo ""
  fi
  if [ ${skip_snap} -ne 1 ]; then
    make_snap_tree
  else
    echo "Skipping making snap tree"
    echo ""
  fi
  if [ ${skip_lxd} -ne 1 ]; then
    start_container
  fi 
  if [ ! -z "${crt_file}" ]; then
    add_ca_crt
  fi
  configure_container
}

while :; do
  case $1 in
      -h|-\?|--help) # Call "show_help" function to display a synopsis, then exit.
          show_help
          exit
          ;;
      ${run_it_arg}) # Takes an option argument, ensuring it has been specified.
          run_it=1
          ;;
      --)              # End of all options.
          shift
          break
          ;;
      -su|--skip-ufw)
          skip_ufw=1
          ;;
      -sd|--skip-dep)
          skip_dep=1
          ;;
      -si|--skip-lxi)
          skip_lxi=1
          ;;
      -sn|--skip-lxn)
          skip_lxn=1
          ;;
      -sl|--skip-lxd)
          skip_lxd=1
          ;;
      -sc|--skip-checkout)
          skip_co=1
          ;;
      -ss|--skip-snap)
          skip_snap=1
          ;;
      -c|--ca-crt)
          crt_file=$2
          shift
          ;;
      -?*)
          printf 'WARN: Unknown option: %s\n' "$1" >&2 # Too dangerous, exit and show help
          exit
          ;;
      *) # Default case: If no more options then break out of the loop.
          break
  esac
  shift
done

if [ ${run_it} -eq 1 ]; then
  run
else
  show_help
fi
