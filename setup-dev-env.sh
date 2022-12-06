#!/bin/sh
#
# This script sets up a development environment for MAAS
#

# set -e might be too strict for some tasks
#   e.g cloning in an existing directory usually works
set -e

# source config and setup variables
. ./config.sh

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
skip_co=0

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
  echo "      (if configured) add a branch for your launcpad account"
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
  echo "  -su --skip-ufw    skip disabling ufw"
  echo "  -sd --skip-dep    skip installing dependencies to your local system"
  echo "  -si --skip-lxi    skip initializing lxd (lxd auto init)"
  echo "  -sl --skip-lxd    skip setting up lxd profiles, networks and starting container"
  echo "  -sc --skip-checkout skip checking out the code and building the snap tree"
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
  echo "########################"
  echo "Setting up the snap tree"
  make snap-tree
  echo "..done"
  echo
}

setup_lxd() {
  echo "#######################"
  echo "Setting up LXD networks"
  echo
  echo "  - Note that LXD per default does not assign networks to projects"
  cd ${script_dir}
  
  # if [ -n ${MAAS_LXD_PROJECT} ] && [ ${MAAS_LXD_PROJECT} != "default" ]; then
  #   lxc project create ${MAAS_LXD_PROJECT}
  #   lxc project set ${MAAS_LXD_PROJECT} features.networks true
  # else
  #   MAAS_LXD_PROJECT=default
  # fi
 
  # lxc --project=${MAAS_LXD_PROJECT} network create maas-ctrl
  lxc network create maas-ctrl
  # cat << __EOF | lxc --project=${MAAS_LXD_PROJECT} network edit maas-ctrl
  cat << __EOF | lxc network edit maas-ctrl
config:
  dns.domain: maas-ctrl
  ipv4.address: ${MAAS_CONTROL_IP_RANGE}/24
  ipv4.dhcp: "true"
  ipv4.dhcp.ranges: ${control_network_prefix}.16-${control_network_prefix}.31
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: maas-ctrl
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF

  # lxc --project=${MAAS_LXD_PROJECT} network create maas-kvm
  lxc network create maas-kvm
  # cat << __EOF | lxc --project=${MAAS_LXD_PROJECT} network edit maas-kvm
  cat << __EOF | lxc network edit maas-kvm
config:
  ipv4.address: ${MAAS_MANAGEMENT_IP_RANGE}/24
  ipv4.dhcp: "false"
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: maas-kvm
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  echo "..done"
  echo
  
  # echo "################################"
  # echo "Setting LXD HTTPS address to 8443"
  # lxc config set core.https_address [::]:8443
  # echo "..done"
  # echo

  echo "#######################"
  echo "Setting up LXD profiles"
  # lxc profile create --project=${MAAS_LXD_PROJECT} ${MAAS_CONTAINER_NAME}
  lxc profile create ${MAAS_CONTAINER_NAME}
  # cat <<EOF | lxc profile edit --project=${MAAS_LXD_PROJECT} ${MAAS_CONTAINER_NAME}
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
        network: maas-ctrl
    eth1:
        type: nic
        name: eth1
        network: maas-kvm
EOF
  echo "..done"
  echo
}

start_container() {
  echo "##################################################################"
  echo "Setting up MAAS development container named ${MAAS_CONTAINER_NAME}"
  lxc launch ubuntu:jammy ${MAAS_CONTAINER_NAME} -p default -p ${MAAS_CONTAINER_NAME}
  echo "..waiting for container to be ready.."
  lxc exec ${MAAS_CONTAINER_NAME} -- cloud-init status --wait
  echo "..done"
  echo
}

configure_container() {
  cd ${script_dir}
  container_ip=$(lxc list -c4 --format csv ${MAAS_CONTAINER_NAME} | grep "${control_network_prefix}"| cut -d' ' -f1)
  echo "################################################################"
  echo "SSHing into ${MAAS_CONTAINER_NAME} (${container_ip}) development and setting it up"
  # could pass vars in there with ssh ubuntu@${container_ip} 'bash -s' < setup-region-via-ssh.sh var1 var2 ...
  ssh -o "StrictHostKeyChecking no" ubuntu@${container_ip} MAAS_CONTROL_IP_RANGE=${MAAS_CONTROL_IP_RANGE} MAAS_MANAGEMENT_IP_RANGE=${MAAS_MANAGEMENT_IP_RANGE} bash -s < setup-region-via-ssh.bash
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
    echo "Skipping local dependencie"
    echo ""
  fi
  if [ ${skip_lxi} -ne 1 ]; then
    init_lxd
  else
    echo "Skipping LXD init"
    echo ""
  fi
  if [ ${skip_lxd} -ne 1 ]; then
    setup_lxd
  else
    echo "Skipping LXD setup"
    echo ""
  fi
  if [ ${skip_co} -ne 1 ]; then
    setup_code
  else
    echo "Skipping code checkout and snap building"
    echo ""
  fi
  if [ ${skip_lxd} -ne 1 ]; then
    start_container
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
      -sl|--skip-lxd)
          skip_lxd=1
          ;;
      -sc|--skip-checkout)
          skip_co=1
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
 
