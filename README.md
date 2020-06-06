# gentoo-builder
Build gentoo linux.

# Setup
You will need some software installed on your system:

    parted

To manually install on a Debian/Ubuntu system, run:

    sudo apt install parted

Or:

    sudo make deps

# Information
...

# Installation
To make a default minimal gentoo system:

    sudo make def

# Removal
If you decide you would like to completely destroy everything:

    sudo make remove

If you are or were, currently in the middle pf a build, make sure to **FIRST** run:

    sudo make clean

(WIP)
(Read the Makefile for more/current information)
