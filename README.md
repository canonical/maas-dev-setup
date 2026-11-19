# An Opinionated Setup of a MAAS Dev Environment

## Goals of this project

To make the setup of a MAAS development environment super simple.
Think of this as a one click installer.

## Requirements

* Ubuntu (maybe Debian)
* `sudo` and the ability to run commands as root
* To use MAAS a decent amount of RAM would be good (> 8GB)
* An authentication key setup on Github for your local machine (see [GitHub docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account))


In the best case LXD is not configured on your system. If it isn't, run the 
following commands and restart your machine:
```bash
sudo adduser $USER lxd
newgrp lxd
```
However, if you have configured LXD and have running
containers and network configurations, this is not a problem but make sure
that the following names/network ranges are not yet used by LXD (or change values in 
`config.sh`).

* a profile in LXDs default project called `$MAAS_CONTAINER_NAME`
* two networks named `maas-ctrl` and `maas-kvm`
  * these networks will use the IP ranges `$MAAS_CONTROL_IP_RANGE` and `MAAS_MANAGEMENT_IP_RANGE`


## How to run this script?

1. Edit the `config.sh` file according to your needs.
2. Run this to see your options

```sh
./setup-dev-env.sh
```
3. Run this to start
```sh
./setup-dev-env.sh --ok
```

If you would like to tear down your MAAS dev environment completely,
do the following:

* remove everything from LXD (e.g. containers, profiles, networks, ...) for all projects
  * you can use [LXD Delete All](https://github.com/tmerten/lxd-delete-all) for this job
* remove your [libvirt](https://libvirt.org/) network definitions (`virsh net-destroy` and `virsh net-undefine` for all networks)
* delete (or move) your current maas source code

## What happens if I run this script?

### Attention

This script was carefully crafted and does not contain any destructive commands.
Still it may install dependencies that might break your system.

The script was tested on Ubuntu 22:10 and 24.04 LTS.

### No, really. What happens?

The script will:

  * DISABLE YOUR UFW FIREWALL (to make sure lxd connections work)
  * Install git, make, lxd, snapcraft, libvirt with qemu
  * Clone the source code and (if configured) add a branch for your launcpad account
  * Setup LXD to have a MAAS development container, profiles and networks
  * Setup bridges so that MAAS can reach your network
  * Create `MAAS_MACHINE_COUNT` empty LXD VMs on the `maas-kvm` network and add them to MAAS as machines using the `lxd` power driver
    * An RSA client certificate is generated in `.lxd-power/` (git-ignored), trusted by your local LXD (restricted to the `default` project) and copied into the MAAS container
    * The VMs use the `MAAS_MACHINE_PROFILE` LXD profile in the `default` project.

Basically the script mimics the steps described in [this discourse post](https://discourse.maas.io/t/setting-up-a-minimal-dev-environment-with-lxd/6318) and configures your maas-dev host to be able to connect to your local LXD.

The script will stop on any error, so please be sure to skip stages, if you have already done them.

You can skip some of those stages using the `-sX` arguments. Run `./setup-dev-env.sh --help` to see your options.

## Adding an SSL certificate to the trusted CA's

If you need MAAS to accept a self-signed SSL certificate, you must add the certificate (in PEM format) to the trusted CAs within the lxd container. You can do this with the `-c` or `--ca-crt` option, as such:

```bash
./setup-dev-env.sh --ok -c /path/to/cert.crt
```

## Adding more machines

Bump `MAAS_MACHINE_COUNT` in `config.sh` and skip every other stage. Existing VMs and machines are reused, so only the new ones get created:

```bash
./setup-dev-env.sh -su -sd -si -sn -sp -sc -ss -sl -sr --ok
```
