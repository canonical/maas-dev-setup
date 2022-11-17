# An Opinionated Setup of a MAAS Dev Environment

## Goals of this project

To make the setup of a MAAS development environment super simple.
Think of this as a one click installer.

## How to run this script?

1. Edit the `config.sh` file according to your needs.
2. Run this to see your options

```sh
./setup-dev-env.sh
```
3. Run this to start
```sh
./setup-dev-env.sh --yes
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

The script was tested on Ubuntu 22:10.

### No, really. What happens?

The script will:

  * DISABLE YOUR UFW FIREWALL (to make sure lxd connections work)
  * Install git, make, lxd, snapcraft, libvirt with qemu
  * Clone the source code and (if configured) add a branch for your launcpad account
  * Setup LXD to have a MAAS development container
  * Setup bridges so that MAAS can reach your network
  * Connect your local LXD to the MAAS development container so that MAAS can provision virtual machines

Basically the script mimics the steps described in [this discord post](https://discourse.maas.io/t/setting-up-a-minimal-dev-environment-with-lxd/6318) and configures your maas-dev host to be able to connect to your local LXD.

The script will stop on any error, so please be sure to skip stages, if you have already done them.

You can skip some of those stages using the `-sX` arguments. Run `./setup-dev-env.sh --help` to see your options.
