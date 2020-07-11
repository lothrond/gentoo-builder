########################################################################
SHELL := /bin/bash
CURRDIR := $(shell pwd)
########################################################################
## Gentoo ENVIRONMENT:
########################################################################

ARCH ?= native
MAKEOPTS ?= "-j 2"

GENTOO ?= /mnt/gentoo
GENTOO_IMAGE ?= /tmp/gentoo.img

KEEP ?= $(HOME)


# Define size (in GB) of virtual block device image:
GENTOO_SIZE ?= 8
BS := 1024

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
## Dependencies:
########################################################################
# (Must be done manually BEFORE build to ensure dependencies).

DEPS:= parted wget tar dosfstools

# Debian/Ubuntu:
.PHONY: install-deps-deb
install-deps-deb:
	apt install -y $(DEPS)

#######################################################################################
## Host chroot build operations:
#######################################################################################

chroot: block_device uefi_partition uefi_fs uefi_mount stage3 portage kernelfs

DEVICE := $$(losetup -j $(GENTOO_IMAGE) | cut -d ':' -f 1)
COUNT := $$(( $(BS) * $(GENTOO_SIZE) * $(BS) ))

block_device:
	dd bs=$(BS) if=/dev/zero of=$(GENTOO_IMAGE) count=$(COUNT) status=progress
	losetup -fP $(GENTOO_IMAGE)
	mkfs.ext4 "$(DEVICE)"

.PHONY: uefi_partition
uefi_partition: $(GENTOO_IMAGE)
	[ $(DEVICE) ] || losetup -fP $(GENTOO_IMAGE)
	wipefs -af $(DEVICE)
	parted -a optimal $(DEVICE) -- mklabel gpt \
		unit mib \
		mkpart "efi" fat32 1 261 \
		set 1 esp on \
		mkpart "rootfs" ext4 261 100% \
		print

.PHONY: uefi_fs
uefi_fs: $(GENTOO_IMAGE)
	-[ $(DEVICE) ] || losetup -fP $(GENTOO_IMAGE)
	mkfs.fat -F32 $(DEVICE)p1
	mkfs.ext4 $(DEVICE)p2

.PHONY: mbr_partition
default_partition_mbr: $(GENTOO_IMAGE)
	wipefs -af $(DEVICE)
	parted -a optimal $(DEVICE) -- mklabel msdos \
		mkpart primary ext2 2 202 \
		set 1 boot on \
		mkpart primary linux-swap 202 802 \
		mkpart primary ext4 802 -1s \
		print

.PHONY: mbr_fs
mbr_fs: $(GENTOO_IMAGE)
	-[ $(DEVICE) ] || losetup -fP $(GENTOO_IMAGE)
	mkfs.ext2 $(DEVICE)p1
	mkswap $(DEVICE)p2
	mkfs.ext4 $(DEVICE)p3

.PHONY: uefi_mount
uefi_mount: $(GENTOO_IMAGE)
	-[ $(DEVICE) ] || losetup -fP $(GENTOO_IMAGE)
	-[ -d $(GENTOO) ] || mkdir -pv $(GENTOO)
	mount $(DEVICE)p2 $(GENTOO)

STAGE3_URL := https://mirrors.kernel.org/gentoo/releases/amd64/autobuilds/current-stage3-amd64
CURRENT_STAGE3 := $$(cat /tmp/current-stage3-amd64 | grep stage3- | grep amd64 | grep .tar | cut -d '"' -f 2 | head -n 1)
SHA512SUM_VERIFIED := \
	$$(cat $(GENTOO)/$(CURRENT_STAGE3).DIGESTS.asc | grep -A 1 -i sha512 | grep -v SHA | grep -v .CONTENTS | grep "stage3" | cut -d ' ' -f 1)
STAGE3_SHA512SUM := $$(sha512sum $(GENTOO)/$(CURRENT_STAGE3) | cut -d ' ' -f 1)

# Gentoo stage3 tarball:
stage3:
	# Get latest stage3 tarball.
	wget --https-only $(STAGE3_URL) -P /tmp
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3) -P $(GENTOO)
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).CONTENTS.gz -P $(GENTOO)
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).DIGESTS -P $(GENTOO)
	wget --https-only $(STAGE3_URL)/$(CURRENT_STAGE3).DIGESTS.asc -P $(GENTOO)
	# Verify stage3 sha512sum.
	[ $(STAGE3_SHA512SUM) == $(SHA512SUM_VERIFIED) ] && \
		tar -xpvf $(GENTOO)/$(CURRENT_STAGE3) --xattrs-include='*.*' --numeric-owner -C $(GENTOO)
	# Cleanup/store stage3
	mv -v $(GENTOO)/$(CURRENT_STAGE3) $(GENTOO)/root
	mv -v $(GENTOO)/$(CURRENT_STAGE3).CONTENTS.gz $(GENTOO)/root
	mv -v $(GENTOO)/$(CURRENT_STAGE3).DIGESTS $(GENTOO)/root
	mv -v $(GENTOO)/$(CURRENT_STAGE3).DIGESTS.asc $(GENTOO)/root

# Default minimal portage configuration.
.PHONY: portage
portage: $(GENTOO_IMAGE)
	sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=$(ARCH) -O2 -pipe"/g' \
		$(GENTOO)/etc/portage/make.conf
	echo -e "\n# Other"
	echo -e "MAKEOPTS=\"$(MAKEOPTS)\"" >> $(GENTOO)/etc/portage/make.conf
	echo -e GENTOO_MIRRORS="\"$(M0) $(M1) $(M2) $(M3) $(M4)\"" >> \
		$(GENTOO)/etc/portage/make.conf
	mkdir -p $(GENTOO)/etc/portage/repos.conf
	cp $(GENTOO)/usr/share/portage/config/repos.conf \
		$(GENTOO)/etc/portage/repos.conf/gentoo.conf

# Prepare kernel fs for chroot.
.PHONY: kernelfs
kernelfs: $(GENTOO_IMAGE)
	cp --dereference /etc/resolv.conf $(GENTOO)/etc
	mount --types proc /proc $(GENTOO)/proc
	mount --rbind /sys $(GENTOO)/sys
	mount --make-rslave $(GENTOO)/sys
	mount --rbind /dev $(GENTOO)/dev
	mount --make-rslave $(GENTOO)/dev
	-[ -L /dev/shm ] && { rm /dev/shm && mkdir /dev/shm ;}
	mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
	chmod 1777 /dev/shm

########################################################################
# Chroot gentoo build operations:
########################################################################

.PHONY: gentoo
gentoo:
	-[ -f $(GENTOO)/Makefile ] || cp $(CURRDIR)/Makefile $(GENTOO)
	chroot $(GENTOO) make profile

# Setup minimal gentoo profile
.PHONY: profile
profile:
	$(shell source /etc/profile)
	mount $(DEVICE)p1 /boot
	emerge-webrsync
	eselect profile set $(PROFILE_CORE)
	emerge --update --verbose --deep --newuse @world
	echo "$(TIMEZONE)" > /etc/timezone
	emerge --config sys-libs/timezone-data
	sed -i 's/#en_US\ ISO-8859-1/en_US\ ISO-8859-1/g' /etc/locale.gen
	sed -i 's/en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/g' /etc/locale.gen
	locale-gen

########################################################################
## Other useful operations:
########################################################################

# Keep block device image
.PHONY: keep
keep: $(GENTOO_IMAGE)
	mv -v $(GENTOO_IMAGE) $(KEEP)

# Cleanup build.
# (Useful for failed or infinished builds.)
.PHONY: clean
clean:
	umount -R $(GENTOO) | losetup -d $(DEVICE)
	rm $(GENTOO_IMAGE)
	rmdir $(GENTOO)
	[ -f /tmp/current-stage3-amd64 ] && rm /tmp/current-stage3-amd64

########################################################################
