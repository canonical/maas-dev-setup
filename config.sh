#
# Configuration variables for setup-dev-env-.sh
#

# Instance name used to namespace all LXD resources (container, profile, networks, VM host).
# This allows running multiple MAAS versions side by side without conflicts.
# Must be a numeric MAAS version string, max 5 digits (kernel bridge name limit of 15 chars).
# Examples: "36" for MAAS 3.6, "38" for MAAS 3.8, "310" for MAAS 3.10.
MAAS_INSTANCE="38"

# Depending on the MAAS version, that you are running,
# you should pick the appropriate ubuntu version.
#
# These are currently noble for 3.6+, jammy for 3.4, 3.5
UBUNTU_VERSION="noble"

# This assumes that your maas source is installed next to this project,
# in a directory named after the instance (e.g. ../maas-38 for MAAS_INSTANCE="38").
# Each instance needs its own checkout so their snap trees don't clobber each other.
MAAS_SRC="../maas-${MAAS_INSTANCE}"

# This is the name of container MAAS will be running in
# as well as the name for the related LXD profile
MAAS_CONTAINER_NAME="maas-${MAAS_INSTANCE}"

# If you enter a launchpad-id, the script can automatically setup your local fork
# and retrieve your public ssh key from launchpad
MAAS_LAUNCHPAD_ID="aloiziomacedo"

# The LXD project in which this installation should reside
# Leave empty or set to "default" to use the default project
# MAAS_LXD_PROJECT="maas-dev"

# LXD network names — derived from MAAS_INSTANCE to avoid conflicts between versions.
# Shortened base names keep the resulting bridge interface name under the 15-char kernel limit.
MAAS_CTRL_NETWORK="maas-ctrl-${MAAS_INSTANCE}"
MAAS_KVM_NETWORK="maas-kvm-${MAAS_INSTANCE}"
MAAS_IPV6_NETWORK="maas-ip6-${MAAS_INSTANCE}"
MAAS_DUAL_STACK_NETWORK="maas-ds-${MAAS_INSTANCE}"

# IP ranges are automatically derived from MAAS_INSTANCE so that different instances
# do not conflict with each other.
#
# MAAS_INSTANCE must be a numeric MAAS version string (e.g. "36", "38", "310", "40").
# The third IPv4 octet is computed as: major * 30 + minor, where the first digit is
# the major version and the remaining digits are the minor version.
# Examples: "36" → 3*30+6 = 96,  "310" → 3*30+10 = 100,  "40" → 4*30+0 = 120.
#
# To override any range, set the variable explicitly after this block.
case "${MAAS_INSTANCE}" in
*[!0-9]*)
  echo "ERROR: MAAS_INSTANCE must be a numeric MAAS version string (e.g. \"36\", \"38\", \"310\")."
  echo "  Got: '${MAAS_INSTANCE}'"
  exit 1
  ;;
*)
  _major="${MAAS_INSTANCE%"${MAAS_INSTANCE#?}"}" # first character (major version digit)
  _minor="${MAAS_INSTANCE#?}"                    # remaining characters (minor version)
  : "${_minor:=0}"
  _instance_octet=$((_major * 30 + _minor))
  ;;
esac
if [ "${_instance_octet}" -lt 1 ] || [ "${_instance_octet}" -gt 253 ]; then
  echo "ERROR: derived IP octet ${_instance_octet} for MAAS_INSTANCE='${MAAS_INSTANCE}' is out of range [1, 253]."
  echo "  Choose a different MAAS_INSTANCE value."
  exit 1
fi
_instance_hex=$(printf '%04x' "${_instance_octet}")

# Note: netmasks will be set to /24 (IPv4) or /64 (IPv6); IP_RANGEs must end with .1 / ::1.
MAAS_CONTROL_IP_RANGE="10.10.${_instance_octet}.1"
MAAS_MANAGEMENT_IP_RANGE="10.20.${_instance_octet}.1"
MAAS_IPV6_IP_RANGE="fd42:${_instance_hex}:b08a:3d6c::1"
MAAS_DUAL_STACK_IPV4_RANGE="10.30.${_instance_octet}.1"
MAAS_DUAL_STACK_IPV6_RANGE="fd42:${_instance_hex}:b08b:3d6d::1"
