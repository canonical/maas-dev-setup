#
# Configuration variables for setup-dev-env-.sh
#

# Instance name used to namespace all LXD resources (container, profile, networks, VM host).
# This allows running multiple MAAS versions side by side without conflicts.
# Must be at most 5 alphanumeric/hyphen characters (kernel bridge name limit of 15 chars).
# Examples: "36" for MAAS 3.6, "37" for MAAS 3.7, "main" for main branch.
MAAS_INSTANCE="dev"

# Depending on the MAAS version, that you are running,
# you should pick the appropriate ubuntu version.
#
# These are currently noble for 3.6+, jammy for 3.4, 3.5
UBUNTU_VERSION="noble"

# This assumes that your maas source should be installed next to this project.
MAAS_SRC="../maas"

# This is the name of container MAAS will be running in
# as well as the name for the related LXD profile
MAAS_CONTAINER_NAME="maas-${MAAS_INSTANCE}"

# If you enter a launchpad-id, the script can automatically setup your local fork
# and retrieve your public ssh key from launchpad
MAAS_LAUNCHPAD_ID=""

# The LXD project in which this installation should reside
# Leave empty or set to "default" to use the default project
# MAAS_LXD_PROJECT="maas-dev"

# LXD network names — derived from MAAS_INSTANCE to avoid conflicts between versions.
# Shortened base names keep the resulting bridge interface name under the 15-char kernel limit.
MAAS_CTRL_NETWORK="maas-ctrl-${MAAS_INSTANCE}"
MAAS_KVM_NETWORK="maas-kvm-${MAAS_INSTANCE}"
MAAS_IPV6_NETWORK="maas-ip6-${MAAS_INSTANCE}"
MAAS_DUAL_STACK_NETWORK="maas-ds-${MAAS_INSTANCE}"

# The netmasks for the LXD networks you would like to use.
# Note:
#   netmasks will be set to /24 and IP_RANGEs have to end with .1 / ::1
#   Each instance MUST use different IP ranges to avoid subnet conflicts.
MAAS_CONTROL_IP_RANGE="10.10.0.1"
MAAS_MANAGEMENT_IP_RANGE="10.20.0.1"
MAAS_IPV6_IP_RANGE="fd42:be3f:b08a:3d6c::1"
MAAS_DUAL_STACK_IPV4_RANGE="10.30.0.1"
MAAS_DUAL_STACK_IPV6_RANGE="fd42:be3f:b08b:3d6d::1"
