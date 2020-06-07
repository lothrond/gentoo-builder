########################################################################
SHELL := /bin/bash
CURRDIR := $(shell pwd)
########################################################################
## BEGIN GENTOO DEFAULT ENVIRONMENT:
########################################################################

GENTOO ?= $(CURRDIR)/gentoo
GENTOO_CHROOT ?= $(GENTOO)/chroot
GENTOO_IMAGE ?= $(GENTOO)/gentoo.img

# Define size (in GB) of virtual block device image:
GENTOO_SIZE ?= 8

# Portage options:
MAKEOPTS ?= "-j 2"
ARCH ?= native

# OpenRC options:
TIMEZONE ?= America/New_York

# Desktop profiles
PROFILE_CORE := default/linux/amd64/17.1

# Mirrors
M0 ?= https://gentoo.osuosl.org/
M1 ?= https://mirrors.evowise.com/gentoo/
M2 ?= https://gentoo.ussg.indiana.edu/
M3 ?= https://mirrors.rit.edu/gentoo/
M4 ?= https://mirror.sjc02.svwh.net/gentoo/

########################################################################
## END GENTOO DEFAULT ENVIRONMENT.
########################################################################

# Virtual block device image size:
BS := 1024
COUNT := $(shell echo $$(( $(BS) * $(GENTOO_SIZE) * $(BS) )))

# Virtual block device image:
DEVICE := $(shell losetup -j $(GENTOO_IMAGE) | cut -d ':' -f 1)

# Check if virtutal block device image is ready:
DEVICE_READY := $(shell losetup -j $(GENTOO_IMAGE) | wc -l)

# Gentoo stage3 tarball:
STAGE3_URL := https://mirrors.kernel.org/gentoo/releases/amd64/autobuilds/current-stage3-amd64/
CURRENT_STAGE3 := $(shell cat /tmp/index.html | grep stage3- | grep amd64 | grep .tar | cut -d '"' -f 2 | head -n 1)

# Verify stage3 tarball sha512sum.
SHA512SUM_VERIFIED := \
	$(shell cat $(GENTOO)/$(CURRENT_STAGE3).DIGESTS.asc | grep -A 1 -i sha512 | grep -v SHA | grep -v .CONTENTS | grep "stage3" | cut -d ' ' -f 1)
STAGE3_SHA512SUM := $(shell sha512sum $(GENTOO)/$(CURRENT_STAGE3) | cut -d ' ' -f 1)

#######################################################################################
## Install dependencies:
#######################################################################################
# (Must be done manually BEFORE build to ensure dependencies).

# Debian/Ubuntu:
.PHONY: deps
deps:
	apt install -y parted wget tar

#######################################################################################
## Make default minimal system:
#######################################################################################
.PHONY: def
def: dir image def-partition def-fs def-mount stage3 portage kernelfs def-chroot

#######################################################################################
## Host build operations:
#######################################################################################

# Create working directory
.PHONY: dir
dir:
	-[ -d  $(GENTOO) ] || mkdir -pv $(GENTOO)

# Create virtual block device image.
.PHONY: image
image: $(GENTOO)
	dd bs=$(BS) if=/dev/zero of=$(GENTOO_IMAGE) count=$(COUNT) status=progress
	losetup -fP $(GENTOO_IMAGE)
	mkfs.ext4 $(DEVICE)

# Default/minimal partition.
.PHONY: def-partition
def-partition: $(GENTOO_IMAGE) $(DEVICE)
	[ $(DEVICE_READY) -eq 1 ]
	wipefs -af $(DEVICE)
	parted -a optimal $(DEVICE) -- mklabel msdos \
		mkpart primary ext2 2 202 \
		set 1 boot on \
		mkpart primary linux-swap 202 802 \
		mkpart primary ext4 802 -1s \
		print

# Default/minimal filesystems.
.PHONY: def-fs
def-fs: $(GENTOO_IMAGE) $(DEVICE)
	[ $(DEVICE_READY) -eq 1 ]
	mkfs.ext2 $(DEVICE)p1
	mkswap $(DEVICE)p2
	mkfs.ext4 $(DEVICE)p3

# Mount default/minimal filesystems.
.PHONY: def-mount
def-mount: $(GENTOO_IMAGE) $(DEVICE)
	-[ -d $(GENTOO_CHROOT) ] || mkdir -pv $(GENTOO_CHROOT)
	mount $(DEVICE)p3 $(GENTOO_CHROOT)

# Get latest stage3 tarball.
.PHONY: stage3
stage3: $(STAGE3) $(GENTOO_CHROOT)
	wget --https-only $(STAGE3_URL) -P /tmp
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3) -P $(GENTOO)
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).CONTENTS.gz -P $(GENTOO)	
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).DIGESTS -P $(GENTOO)
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).DIGESTS.asc -P $(GENTOO)
	[ $(STAGE3_SHA512SUM) == $(SHA512SUM_VERIFIED) ]
	tar -xpf $(GENTOO)/$(CURRENT_STAGE3) --xattrs-include='*.*' --numeric-owner -C $(GENTOO_CHROOT)

# Default/minimal portage configuration.
.PHONY: portage
portage: $(GENTOO_CHROOT)
	sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=$(ARCH) -O2 -pipe"/g' \
		$(GENTOO_CHROOT)/etc/portage/make.conf
	echo "MAKEOPTS=$(MAKEOPTS)" >> $(GENTOO_CHROOT)/etc/portage/make.conf
	echo GENTOO_MIRRORS="\"$(M0) $(M1) $(M2) $(M3) $(M4)\"" >> \
		$(GENTOO_CHROOT)/etc/portage/make.conf
	mkdir -p $(GENTOO_CHROOT)/etc/portage/repos.conf
	cp $(GENTOO_CHROOT)/usr/share/portage/config/repos.conf \
		$(GENTOO_CHROOT)/etc/portage/repos.conf/gentoo.conf

# Prepare kernel fs for chroot.
.PHONY: kernelfs
kernelfs: $(GENTOO_CHROOT)
	cp --dereference /etc/resolv.conf $(GENTOO_CHROOT)/etc
	mount --types proc /proc $(GENTOO_CHROOT)/proc
	mount --rbind /sys $(GENTOO_CHROOT)/sys
	mount --make-rslave $(GENTOO_CHROOT)/sys
	mount --rbind /dev $(GENTOO_CHROOT)/dev
	mount --make-rslave $(GENTOO_CHROOT)/dev
	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
	mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
	chmod 1777 /dev/shm

########################################################################
# Chroot build operations:
########################################################################

.PHONY: check-chroot-makefile:
check-chroot-makefile: $(GENTOO_CHROOT)
	-[ $(GENTOO_CHROOT)/Makefile ] || cp $(CURRDIR)/Makefile $(GENTOO_CHROOT)

.PHONY: def-chroot:
def-profile: $(GENTOO_CHROOT) check-chroot-makefile
	chroot $(GENTOO_CHROOT) /bin/bash -- make def-profile
	
.PHONY: def-profile:
def-profile:
	$(shell source /etc/profile) \
		mount $(DEVICE)p1 /boot \
		emerge-webrsync \
		eselect profile set $(PROFILE_CORE) \
		emerge --ask --verbose --update --deep --newuse @world \
		echo "$(TIMEZONE)" > /etc/timezone \
		emerge --config sys-libs/timezone-data \
		sed -i 's/#en_US\ ISO-8859-1/en_US\ ISO-8859-1/g' /etc/locale.gen \
		sed -i 's/en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/g' /etc/locale.gen \
		locale-gen

########################################################################
## Other useful operations:
########################################################################

# Enter chroot
# (Just enter the gentoo chroot without building, if exisis)
.PHONY: enter_def
enter: $(GENTOO_CHROOT) $(DEVICE)
	losetup -fP $(DEVICE)
	mount $(DEVICE)p3 $(GENTOO_CHROOT)
	mount $(DEVICE)p2 $(GENTOO_CHROOT)/boot
	chroot $(GENTOO_CHROOT)/bin/bash

# Cleanup after build.
# (Useful for failed or infinished builds.)
.PHONY: clean
clean:
	losetup -d $(DEVICE)
	umount -Rf $(GENTOO_CHROOT)

# Remove everything (start from scratch).
.PHONY: remove
remove: $(GENTOO)
	rm -rfv $(GENTOO)

########################################################################
