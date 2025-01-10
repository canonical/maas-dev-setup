#
# Configuration variables for setup-dev-env-.sh
#

# Depending on the MAAS version, that you are running,
# you should pick the appropriate ubuntu version.
#
# These are currently noble for 3.6+, jammy for 3.4, 3.5
UBUNTU_VERSION="noble"

# This assumes that your maas source should be installed next to this project, e.g.
# $HOME/src/setup-maas-dev-env/ --> $HOME/src/maas/
MAAS_SRC="../maas"

# This is the name of container MAAS will be running in
# as well as the name for the related LXD profile
MAAS_CONTAINER_NAME="maas-dev"

# If you enter a launchpad-id, the script can automatically setup your local fork
# and retrieve your public ssh key from launchpad
MAAS_LAUNCHPAD_ID=""

# The LXD project in which this installation should reside
# Leave empty or set to "default" to use the default project
# MAAS_LXD_PROJECT="maas-dev"

# The netmasks for the LXD networks you would like to use
# Note:
#   netmasks will be set to /24 and IP_RANGEs have to end with .1 / ::1
MAAS_CONTROL_NETWORK="maas-dev"
MAAS_CONTROL_IP_RANGE="10.10.0.1"
MAAS_MANAGEMENT_NETWORK="maas-dev"
MAAS_MANAGEMENT_IP_RANGE="10.20.0.1"
MAAS_IPV6_NETWORK="maas-ipv6"
MAAS_IPV6_IP_RANGE="fd42:be3f:b08a:3d6c::1"
MAAS_DUAL_STACK_NETWORK="maas-dual-stack"
MAAS_DUAL_STACK_IPV4_RANGE="10.30.0.1"
MAAS_DUAL_STACK_IPV6_RANGE="fd42:be3f:b08b:3d6d::1"
