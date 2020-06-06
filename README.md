# crogen
Gentoo bootstrap environment.

# Setup
You will need some software installed on your system:

    parted gnupg

To manually install on a Debian/Ubuntu system, run:

    sudo apt install gnupg parted

Or:

    sudo make deps

Also, make sure to tun the following as a normal user BEFORE building,
in order to preserve ownership of the gnupg database:

    gpg -k

# Information
...

# Installation
To make a default minimal gentoo system:

    sudo make def

Then, cleanup after:

    sudo make clean

# Removal
If you decide you would like to completely destroy everything:

    sudo make remove

If you are or were, currently in the middle pf a build, make sure to **FIRST** run:

    sudo make clean

