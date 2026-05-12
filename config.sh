#
# Configuration variables for setup-dev-env-.sh
#

# Instance name used to namespace all LXD resources (container, profile, networks, VM host).
# This allows running multiple MAAS versions side by side without conflicts.
# Must be a numeric MAAS version string, max 5 digits (kernel bridge name limit of 15 chars),
# or the special value "latest" which uses no suffix and the base IP ranges (x.x.0.x).
# Examples: "36" for MAAS 3.6, "38" for MAAS 3.8, "310" for MAAS 3.10, "latest" for tip.
MAAS_INSTANCE="latest"

# Ubuntu version is derived from MAAS_INSTANCE. Override here if needed.
case "${MAAS_INSTANCE}" in
latest | 38) UBUNTU_VERSION="resolute" ;;
36 | 37) UBUNTU_VERSION="noble" ;;
*) UBUNTU_VERSION="resolute" ;;
esac

# "latest" uses no suffix so all names are unqualified (e.g. "maas", "maas-ctrl").
# All other instances append "-<MAAS_INSTANCE>" to avoid conflicts.
if [ "${MAAS_INSTANCE}" = "latest" ]; then
  _instance_suffix=""
else
  _instance_suffix="-${MAAS_INSTANCE}"
fi

# This assumes that your maas source is installed next to this project,
# in a directory named after the instance (e.g. ../maas-38 for MAAS_INSTANCE="38",
# or ../maas for MAAS_INSTANCE="latest").
# Each instance needs its own checkout so their snap trees don't clobber each other.
MAAS_SRC="../maas${_instance_suffix}"

# This is the name of container MAAS will be running in
# as well as the name for the related LXD profile
MAAS_CONTAINER_NAME="maas-dev${_instance_suffix}"

# If you enter a launchpad-id, the script can automatically setup your local fork
# and retrieve your public ssh key from launchpad
MAAS_LAUNCHPAD_ID="aloiziomacedo"

# The LXD project in which this installation should reside
# Leave empty or set to "default" to use the default project
# MAAS_LXD_PROJECT="maas-dev"

# LXD network names — derived from MAAS_INSTANCE to avoid conflicts between versions.
# Shortened base names keep the resulting bridge interface name under the 15-char kernel limit.
MAAS_CTRL_NETWORK="maas-ctrl${_instance_suffix}"
MAAS_KVM_NETWORK="maas-kvm${_instance_suffix}"
MAAS_IPV6_NETWORK="maas-ip6${_instance_suffix}"
MAAS_DUAL_STACK_NETWORK="maas-ds${_instance_suffix}"

# IP ranges are automatically derived from MAAS_INSTANCE so that different instances
# do not conflict with each other.
#
# "latest" uses octet 0 (base ranges: 10.10.0.x, 10.20.0.x, etc.).
# Numeric instances use: major * 30 + minor as the third IPv4 octet, where the first
# digit is the major version and the remaining digits are the minor version.
# Examples: "36" → 3*30+6 = 96,  "310" → 3*30+10 = 100,  "40" → 4*30+0 = 120.
#
# To override any range, set the variable explicitly after this block.
case "${MAAS_INSTANCE}" in
latest)
  _instance_octet=0
  ;;
*[!0-9]*)
  echo "ERROR: MAAS_INSTANCE must be a numeric MAAS version string (e.g. \"36\", \"38\", \"310\") or \"latest\"."
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
if [ "${_instance_octet}" -gt 253 ]; then
  echo "ERROR: derived IP octet ${_instance_octet} for MAAS_INSTANCE='${MAAS_INSTANCE}' is out of range [0, 253]."
  echo "  Choose a different MAAS_INSTANCE value."
  exit 1
fi
_instance_hex=$(printf '%04x' "${_instance_octet}")

# maas-test-db snap channel derived from MAAS_INSTANCE.
case "${MAAS_INSTANCE}" in
  latest) MAAS_TEST_DB_CHANNEL="latest/edge" ;;
  *)      MAAS_TEST_DB_CHANNEL="${_major}.${_minor}/edge" ;;
esac

# Note: netmasks will be set to /24 (IPv4) or /64 (IPv6); IP_RANGEs must end with .1 / ::1.
MAAS_CONTROL_IP_RANGE="10.10.${_instance_octet}.1"
MAAS_MANAGEMENT_IP_RANGE="10.20.${_instance_octet}.1"
MAAS_IPV6_IP_RANGE="fd42:${_instance_hex}:b08a:3d6c::1"
MAAS_DUAL_STACK_IPV4_RANGE="10.30.${_instance_octet}.1"
MAAS_DUAL_STACK_IPV6_RANGE="fd42:${_instance_hex}:b08b:3d6d::1"
