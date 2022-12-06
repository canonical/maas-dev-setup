#
# Configuration variables for setup-dev-env-.sh
#

# This assumes that your maas source should be installed next to this project, e.gg.
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
#   ! netmasks will be set to /24 and networks should end with .1 !
MAAS_CONTROL_NETWORK="maas-dev"
MAAS_CONTROL_IP_RANGE="10.10.0.1"
MAAS_MANAGEMENT_NETWORK="maas-dev"
MAAS_MANAGEMENT_IP_RANGE="10.20.0.1"
