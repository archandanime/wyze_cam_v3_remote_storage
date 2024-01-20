#!/bin/bash
#

modify_appver="false"


action="$1"
SoC="$2"

RECOVERY_BIN="demo_wcv3.bin"

EXTRACTED_ROOTFS_IMG="rootfs.img"
EXTRACTED_APP_IMG="app.img"

ROOTFS_DIR="rootfs"
APP_DIR="app"
ABACK_DIR="aback"

ROOTFS_SQSH_BLOCKSIZE="128K"
APP_SQSH_BLOCKSIZE="128K"
ABACK_SQSH_BLOCKSIZE="64K"

OUT_KERNEL_IMG="output/stock_${SoC}_kernel.bin"
OUT_ROOTFS_IMG="output/stock_${SoC}_rootfs.bin"
OUT_APP_IMG="output/stock_${SoC}_app.bin"
OUT_ABACK_IMG="output/stock_${SoC}_aback.bin"


function extract_recovery_bin() {
	RECOVERY_BIN_SOURCE=recovery_bin/$(ls recovery_bin | tail -n 1)

	echo "Using recovery bin: $RECOVERY_BIN_SOURCE"

	echo
	echo "Copying recovery bin"
	cp $RECOVERY_BIN_SOURCE $RECOVERY_BIN

	echo
	echo "Extracting recovery bin"

	[ ! -f ${RECOVERY_BIN} ] && { echo "${RECOVERY_BIN} does not exist" ; return 1 ; }

	local kernel_start_addr="64"
	local rootfs_start_addr="2031680"
	local app_start_addr="6029376"
	local RECOVERY_BIN_size=`du -b ${RECOVERY_BIN} | cut -f1`

	local kernel_size=$(( $rootfs_start_addr - $kernel_start_addr))
	local rootfs_size=$(( $app_start_addr - $rootfs_start_addr ))
	local app_size=$(( $RECOVERY_BIN_size - $app_start_addr ))

	echo "    Extracting kernel image from recovery bin"
	[ -f $OUT_KERNEL_IMG ] && { echo "$OUT_KERNEL_IMG exists" ; return 1 ; }
	dd if=${RECOVERY_BIN} of=$OUT_KERNEL_IMG bs=1 skip=$kernel_start_addr count=${kernel_size} status=none

	echo "    Extracting rootfs image from recovery bin"
	[ -f $EXTRACTED_ROOTFS_IMG ] && { echo "$EXTRACTED_ROOTFS_IMG exists" ; return 1 ; }
	dd if=${RECOVERY_BIN} of=$EXTRACTED_ROOTFS_IMG bs=1 skip=$rootfs_start_addr count=$rootfs_size status=none

	echo "    Extracting app image from recovery bin"
	[ -f $EXTRACTED_APP_IMG ] && { echo "$EXTRACTED_APP_IMG exists" ; return 1 ; }
	dd if=${RECOVERY_BIN} of=$EXTRACTED_APP_IMG bs=1 skip=$app_start_addr count=$app_size status=none

	echo "    Decompressing rootfs image"
	[ -d $ROOTFS_DIR ] && { echo "$ROOTFS_DIR directory exists" ; return 1 ; }
	unsquashfs -d $ROOTFS_DIR $EXTRACTED_ROOTFS_IMG >/dev/null

	echo "    Decompressing app image"
	[ -d $APP_DIR ] && { echo "$APP_DIR directory exists" ; return 1 ; }
	unsquashfs -d $APP_DIR $EXTRACTED_APP_IMG >/dev/null
}

function modify_partitions() {
	echo
	echo "Modifying rootfs and app"

	echo "    Copying rootfs_overlay"
	cp -rT rootfs_overlay $ROOTFS_DIR
	find $ROOTFS_DIR -type f -name .gitkeep -delete

	echo
	chmod 644 $ROOTFS_DIR/etc/shadow
	echo "    Patching rootfs"
	cd $ROOTFS_DIR
	for patch_file in ../rootfs_patches/*.patch; do
		echo -n "     + "
		patch -p1 < $patch_file
	done
	cd ..
	chmod 400 $ROOTFS_DIR/etc/shadow

	echo
	echo "    Modifying app.ver files"
	local rootfs_ver=$(cat $ROOTFS_DIR/usr/app.ver | grep appver= | cut -d '=' -f2)
	local app_ver=$(cat $APP_DIR/bin/app.ver | grep appver= | cut -d '=' -f2)
	echo "     + rootfs version: $rootfs_ver"
	echo "     + app version: $app_ver"

	if [[ "$modify_appver" == "true" ]]; then
		sed -i "s/$rootfs_ver/sd_$rootfs_ver/g" $ROOTFS_DIR/usr/app.ver
		sed -i "s/$app_ver/sd_$app_ver/g" $APP_DIR/bin/app.ver

		local new_rootfs_ver=$(cat $ROOTFS_DIR/usr/app.ver | grep appver= | cut -d '=' -f2)
		local new_app_ver=$(cat $APP_DIR/bin/app.ver | grep appver= | cut -d '=' -f2)
		echo "     + new rootfs version: $new_rootfs_ver"
		echo "     + new app version: $new_app_ver"
	else
		echo "     + Skipping modifying appver"
	fi

	echo
	echo "    Disabling mtd-utils to block firmware update"
	for mtd_utils in flashcp flash_erase flash_eraseall; do
		mtd_utils_files=$( find . -name $mtd_utils \( -type f -o -type l \) )
		for mtd_utils_file in $mtd_utils_files; do
			echo "     + $mtd_utils_file" | sed "s/.\/$ROOTFS_DIR//"
			rm $mtd_utils_file
			echo "#!/bin/sh" >> $mtd_utils_file
			echo "" >> $mtd_utils_file
			echo "rm -rf /tmp/Upgrade.tar" >> $mtd_utils_file
			echo "rm -rf /tmp/Upgrade/" >> $mtd_utils_file
			echo "" >> $mtd_utils_file
			echo "pkill -f upgradePrompt1.sh" >> $mtd_utils_file
			echo "pkill -f upgradePrompt2.sh" >> $mtd_utils_file
			echo "pkill -f upgraderun.sh" >> $mtd_utils_file
			echo "" >> $mtd_utils_file
			echo "exit 0" >> $mtd_utils_file
			chmod +x $mtd_utils_file
		done
	done
}

function repack_partitions() {
	echo
	echo "Repacking rootfs"
	[ -f $OUT_ROOTFS_IMG ] && { echo "$OUT_ROOTFS_IMG exists" ; return 1 ; }
	mksquashfs $ROOTFS_DIR $OUT_ROOTFS_IMG -comp xz -all-root -b $ROOTFS_SQSH_BLOCKSIZE >/dev/null
	echo "     + $(du $EXTRACTED_ROOTFS_IMG)"
	echo "     + $(du $OUT_ROOTFS_IMG)"

	echo
	echo "Repacking app"
	[ -f $OUT_APP_IMG ] && { echo "$OUT_APP_IMG exists" ; return 1 ; }
	mksquashfs $APP_DIR $OUT_APP_IMG -comp xz -all-root -b $APP_SQSH_BLOCKSIZE >/dev/null
	echo "     + $(du $EXTRACTED_APP_IMG)"
	echo "     + $(du $OUT_APP_IMG)"

	echo
	echo "Repacking aback"
	[ -f $OUT_ABACK_IMG ] && { echo "$OUT_ABACK_IMG exists" ; return 1 ; }
	mksquashfs $ABACK_DIR $OUT_ABACK_IMG -comp xz -all-root -b $ABACK_SQSH_BLOCKSIZE >/dev/null
	echo "     + $(du $EXTRACTED_APP_IMG)"
	echo "     + $(du $OUT_ABACK_IMG)"
}

function generate_checksum() {
	echo
	echo "Generating sha256sum files"
	for outfile in $OUT_KERNEL_IMG $OUT_ROOTFS_IMG $OUT_APP_IMG $OUT_ABACK_IMG; do
		echo "    For $outfile"
		( cd $(dirname $outfile) && sha256sum $(basename $outfile) > $(basename $outfile).sha256sum )
	done
}

function clean() {
	rm -rf $RECOVERY_BIN $EXTRACTED_ROOTFS_IMG $EXTRACTED_APP_IMG $EXTRACTED_ROOTFS_IMG $EXTRACTED_APP_IMG $ROOTFS_DIR $APP_DIR output
}

function show_syntax() {
		echo "Syntax: ./build.sh <create/clean> <SoC>"
}

[ ! -d output ] && mkdir output

case "${1}" in
	"create")
		if [[ ! "$SoC" == "t31a" ]] && [[ ! "$SoC" == "t31x" ]]; then
			echo "Invalid SoC, only t31a and t31x are supported"
			show_syntax
			exit 1
		fi

		extract_recovery_bin || exit 1
		modify_partitions
		repack_partitions || exit 1
		generate_checksum
		;;
	"clean")
		clean
		;;
	*)
		show_syntax
		;;
esac
