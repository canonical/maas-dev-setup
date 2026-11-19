#!/bin/sh
#
# This script sets up a development environment for MAAS
#

# set -e might be too strict for some tasks
#   e.g cloning in an existing directory usually works
set -e

# source config and setup variables
. ./config.sh

if [ -z "${MAAS_GITHUB_ID}" ]; then
  echo "MAAS_GITHUB_ID is not set in config.sh - it is required to import your SSH keys from your GitHub account via ssh_import_id into the dev container" >&2
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
skip_pro=0
skip_co=0
skip_snap=0
skip_region=0
skip_machines=0
crt_file=""

# Client certificate MAAS uses to drive the host's LXD (lxd power driver).
power_cert_dir="${script_dir}/.lxd-power"
power_cert_name="maas-dev-setup-power"

show_help() {
  echo "Description:"
  echo "  This script sets up a complete dev environment for MAAS."
  echo ""
  echo "  !Attention! This will install packages to your system and"
  echo "    setup profiles, networks and containers for MAAS in LXD"
  echo ""
  echo "  The script does:"
  echo "    * Add rules your UFW firewall (to make sure lxd connections work)"
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
  echo "  -su --skip-ufw    skip configuring UFW"
  echo "  -sd --skip-dep    skip installing dependencies to your local system"
  echo "  -si --skip-lxi    skip initializing LXD (lxd auto init)"
  echo "  -sn --skip-lxn    skip setting up LXD networks"
  echo "  -sp --skip-profile skip setting up the LXD profile"
  echo "  -sl --skip-lxd    skip starting the LXD container"
  echo "  -sc --skip-checkout skip checking out the code"
  echo "  -ss --skip-snap   skip building the snap tree"
  echo "  -sr --skip-region skip installing and configuring MAAS in the container"
  echo "  -sm --skip-machines skip creating LXD VMs and adding them to MAAS as machines"
  echo "  -c  --ca-crt      add the given .crt (PEM format) file to the trusted CAs in the lxd container" 
  echo ""
  echo "Note:"
  echo "  If you installed maas before you likely want to run: ./$0 -su -sd -sv --ok"
  echo "  To only add more machines to an existing setup, bump MAAS_MACHINE_COUNT and run:"
  echo "    $0 -su -sd -si -sn -sp -sc -ss -sl -sr --ok"
  echo ""
}

configure_ufw() {
  if command -v ufw > /dev/null; then
    echo "Configuring UFW..."
    echo "#########################"
    sudo ufw allow in on lxdbr0
    sudo ufw route allow in on lxdbr0
    sudo ufw route allow out on lxdbr0
    sudo ufw allow in on maas-ctrl
    sudo ufw route allow in on maas-ctrl
    sudo ufw route allow out on maas-ctrl
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
  git clone --origin upstream https://github.com/canonical/maas.git . --recurse-submodules
  echo "..done"
  if [ -n "${MAAS_GITHUB_ID:-}" ]; then
    echo "Adding your origin remote git@github.com:${MAAS_GITHUB_ID}/maas.git"
    git remote add origin git@github.com:${MAAS_GITHUB_ID}/maas.git
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

setup_networks() {
  echo "#######################"
  echo "Setting up LXD networks"
  cd ${script_dir}

  lxc network create maas-ctrl
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

  lxc network create maas-kvm
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

  lxc network create maas-ipv6
  cat << __EOF | lxc network edit maas-ipv6
config:
  ipv4.address: none
  ipv6.address: ${MAAS_IPV6_IP_RANGE}/64
  ipv6.dhcp: "false"
  ipv6.nat: "true"
description: "An IPv6 only network"
name: maas-ipv6
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF

  lxc network create maas-dual-stack
  cat << __EOF | lxc network edit maas-dual-stack
config:
  ipv4.address: ${MAAS_DUAL_STACK_IPV4_RANGE}/24
  ipv4.nat: "true"
  ipv4.dhcp: "false"
  ipv6.address: ${MAAS_DUAL_STACK_IPV6_RANGE}/64
  ipv6.nat: "true"
  ipv6.dhcp: "false"
description: "A network for both IPv4 and IPv6"
name: maas-dual-stack
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF
  echo "..done"
  echo

  echo "################################"
  echo "Setting LXD HTTPS address to 8443"
  lxc config set core.https_address [::]:8443
  echo "..done"
  echo
}

setup_profile() {
  echo "#######################"
  echo "Setting up LXD profiles"
  cd ${script_dir}
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
        ssh_import_id:
        - gh:${MAAS_GITHUB_ID}
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
  lxc launch ubuntu:${UBUNTU_VERSION} ${MAAS_CONTAINER_NAME} -p default -p ${MAAS_CONTAINER_NAME}
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
  ssh -o "StrictHostKeyChecking no" ubuntu@${container_ip}\
      MAAS_CONTROL_IP_RANGE=${MAAS_CONTROL_IP_RANGE}\
      MAAS_MANAGEMENT_IP_RANGE=${MAAS_MANAGEMENT_IP_RANGE}\
      MAAS_IPV6_IP_RANGE=${MAAS_IPV6_IP_RANGE}\
      MAAS_DUAL_STACK_IPV4_RANGE=${MAAS_DUAL_STACK_IPV4_RANGE}\
      MAAS_DUAL_STACK_IPV6_RANGE=${MAAS_DUAL_STACK_IPV6_RANGE}\
      bash -s < setup-region-via-ssh.bash
}

container_ssh() {
  container_ip=$(lxc list -c4 --format csv ${MAAS_CONTAINER_NAME} | grep "${control_network_prefix}"| cut -d' ' -f1)
  ssh -o "StrictHostKeyChecking no" ubuntu@${container_ip} "$@"
}

setup_machine_project() {
  if lxc project show ${MAAS_MACHINE_PROJECT} > /dev/null 2>&1; then
    echo "LXD project ${MAAS_MACHINE_PROJECT} already exists, reusing it"
    return
  fi

  echo "#########################################"
  echo "Setting up LXD project ${MAAS_MACHINE_PROJECT}"
  lxc project create ${MAAS_MACHINE_PROJECT}
  echo "..done"
  echo
}

setup_machine_profile() {
  if lxc profile show ${MAAS_MACHINE_PROJECT} --project ${MAAS_MACHINE_PROJECT} > /dev/null 2>&1; then
    echo "LXD profile ${MAAS_MACHINE_PROJECT} already exists, reusing it"
    return
  fi

  # Disable secure boot, the syntax differs depending on the LXD version
  if lxc info | grep -q '^- instance_boot_mode$'; then
    secureboot_config='boot.mode: uefi-nosecureboot'  # LXD >= 6.7
  else
    secureboot_config='security.secureboot: "false"'  # LXD <= 6.6 (incl. 5.21 LTS)
  fi

  echo "#########################################"
  echo "Setting up LXD profile ${MAAS_MACHINE_PROJECT}"
  echo "Note that if you change LXD versions locally, this profile may need to recreated or updated."
  lxc profile create ${MAAS_MACHINE_PROJECT} --project ${MAAS_MACHINE_PROJECT}
  cat <<EOF | lxc profile edit ${MAAS_MACHINE_PROJECT} --project ${MAAS_MACHINE_PROJECT}
config:
  ${secureboot_config}
  limits.cpu: "2"
  limits.memory: 6GiB
description: Empty VMs on maas-kvm, PXE booted and managed by MAAS
devices:
  eth0:
    boot.priority: "1"
    name: eth0
    nictype: bridged
    parent: maas-kvm
    type: nic
  root:
    boot.priority: "0"
    path: /
    pool: default
    size: 8GB
    type: disk
EOF
  echo "..done"
  echo
}

setup_power_cert() {
  echo "#####################################################"
  echo "Setting up the LXD client certificate for MAAS power"
  if [ "$(lxc config get core.https_address)" = "" ]; then
    lxc config set core.https_address [::]:8443
  fi

  # Generate the LXD client certificate for MAAS power if it doesn't already exist
  if [ ! -f "${power_cert_dir}/lxd.crt" ]; then
    mkdir -p "${power_cert_dir}"
    chmod 700 "${power_cert_dir}"
    openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
      -subj "/CN=${power_cert_name}" \
      -keyout "${power_cert_dir}/lxd.key" -out "${power_cert_dir}/lxd.crt"
  fi

  # Get the fingerprint of the generated certificate and add it to LXD trust if not already trusted
  fingerprint=$(openssl x509 -in "${power_cert_dir}/lxd.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | tr 'A-F' 'a-f')
  if lxc config trust show ${fingerprint} > /dev/null 2>&1; then
    echo "Certificate is already trusted by LXD"
  else
    lxc config trust add "${power_cert_dir}/lxd.crt" --name ${power_cert_name} --restricted --projects ${MAAS_MACHINE_PROJECT}
  fi

  echo "..done"
  echo
}

create_machines() {
  # MAAS needs the power cert and key as power parameters. They are only
  # needed in the container while machines are added, so remove them
  # afterwards, including when a step fails.
  trap 'container_ssh rm -f lxd.crt lxd.key || true' EXIT
  lxc file push --uid 1000 --gid 1000 --mode 0600 \
    "${power_cert_dir}/lxd.crt" "${power_cert_dir}/lxd.key" ${MAAS_CONTAINER_NAME}/home/ubuntu/

  i=1
  while [ ${i} -le ${MAAS_MACHINE_COUNT} ]; do
    machine="${MAAS_CONTAINER_NAME}-machine-${i}"
    echo "#############################"
    echo "Setting up LXD VM ${machine}"
    if lxc info ${machine} --project ${MAAS_MACHINE_PROJECT} > /dev/null 2>&1; then
      echo "VM ${machine} already exists, reusing it"
    else
      lxc init --vm --empty --project ${MAAS_MACHINE_PROJECT} --profile ${MAAS_MACHINE_PROJECT} ${machine}
    fi
    mac=$(lxc config get ${machine} volatile.eth0.hwaddr --project ${MAAS_MACHINE_PROJECT})

    container_ssh \
        MACHINE_NAME=${machine}\
        MACHINE_MAC=${mac}\
        LXD_ADDRESS=${MAAS_CONTROL_IP_RANGE}\
        LXD_PROJECT=${MAAS_MACHINE_PROJECT}\
        LXD_CERT=/home/ubuntu/lxd.crt\
        LXD_KEY=/home/ubuntu/lxd.key\
        bash -s < "${script_dir}/add-machine-via-ssh.bash"
    echo
    i=$((i + 1))
  done

  container_ssh rm -f lxd.crt lxd.key
  trap - EXIT
}

setup_machines() {
  if [ ${MAAS_MACHINE_COUNT} -lt 1 ]; then
    echo "MAAS_MACHINE_COUNT is ${MAAS_MACHINE_COUNT}, not creating any machines"
    echo
    return
  fi
  setup_machine_project
  setup_machine_profile
  setup_power_cert
  create_machines
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
    configure_ufw
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
    setup_networks
  else
    echo "Skipping LXD network setup"
    echo ""
  fi
  if [ ${skip_pro} -ne 1 ]; then
    setup_profile
  else
    echo "Skipping LXD profile setup"
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
  if [ ${skip_region} -ne 1 ]; then
    configure_container
  else
    echo "Skipping MAAS region setup"
    echo ""
  fi
  if [ ${skip_machines} -ne 1 ]; then
    setup_machines
  else
    echo "Skipping machine setup"
    echo ""
  fi
  print_done
}

print_done() {
  container_ip=$(lxc list -c4 --format csv ${MAAS_CONTAINER_NAME} | grep "${control_network_prefix}"| cut -d' ' -f1)
  echo "#################################################################"
  echo "We are done!"
  echo
  echo "  MAAS:     http://${container_ip}:5240/MAAS (maas / maas)"
  echo "  Machines: lxc list --project ${MAAS_MACHINE_PROJECT} ${MAAS_CONTAINER_NAME}-machine-"
  echo
  echo "Have fun developing MAAS"
  echo
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
      -sp|--skip-profile)
          skip_pro=1
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
      -sr|--skip-region)
          skip_region=1
          ;;
      -sm|--skip-machines)
          skip_machines=1
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
