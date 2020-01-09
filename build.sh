#!/bin/bash

set -e
set -o pipefail  # Bashism

KALI_DIST="kali-rolling"
KALI_VERSION=""
KALI_VARIANT="default"
IMAGE_TYPE="live"
TARGET_DIR="$(dirname $0)/images"
TARGET_SUBDIR=""
SUDO="sudo"
VERBOSE=""
HOST_ARCH=$(dpkg --print-architecture)
MIRROR=${MIRROR:-/srv/mirror/kali}

image_name() {
	case "$IMAGE_TYPE" in
		live)
			live_image_name "$@"
		;;
		installer)
			installer_image_name "$@"
		;;
	esac
}


live_image_name() {
	local arch=$1

	case "$arch" in
		i386|amd64)
			IMAGE_TEMPLATE="live-image-ARCH.hybrid.iso"
		;;
		armel|armhf)
			IMAGE_TEMPLATE="live-image-ARCH.img"
		;;
	esac
	echo $IMAGE_TEMPLATE | sed -e "s/ARCH/$arch/"
}

installer_image_name() {
	echo "debian-cd/out/kali-$KALI_VERSION-ARCH-1.iso"
}

target_image_name() {
	local arch=$1

	IMAGE_NAME="$(image_name $arch)"
	IMAGE_EXT="${IMAGE_NAME##*.}"
	if [ "$IMAGE_EXT" = "$IMAGE_NAME" ]; then
		IMAGE_EXT="img"
	fi
	if [ "$IMAGE_TYPE" = "live" ]; then
		if [ "$KALI_VARIANT" = "default" ]; then
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}kali-linux-$KALI_VERSION-$KALI_ARCH.$IMAGE_EXT"
		else
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}kali-linux-$KALI_VERSION-$KALI_VARIANT-$KALI_ARCH.$IMAGE_EXT"
		fi
	else
		if [ "$KALI_VARIANT" = "default" ]; then
			echo
			"${TARGET_SUBDIR:+$TARGET_SUBDIR/}kali-linux-$KALI_VERSION-installer-$KALI_ARCH.$IMAGE_EXT"
		else
			echo
			"${TARGET_SUBDIR:+$TARGET_SUBDIR/}kali-linux-$KALI_VERSION-installer-$KALI_VARIANT-$KALI_ARCH.$IMAGE_EXT"
		fi
	fi
}

target_build_log() {
	TARGET_IMAGE_NAME=$(target_image_name $1)
	echo ${TARGET_IMAGE_NAME%.*}.log
}

default_version() {
	case "$1" in
	    kali-*)
		echo "${1#kali-}"
		;;
	    *)
		echo "$1"
		;;
	esac
}

failure() {
	echo "Build of $KALI_DIST/$KALI_VARIANT/$KALI_ARCH $IMAGE_TYPE image failed (see build.log for details)" >&2
	exit 2
}

run_and_log() {
	if [ -n "$VERBOSE" ]; then
		"$@" 2>&1 | tee -a build.log
	else
		"$@" >>build.log 2>&1
	fi
	return $?
}

. $(dirname $0)/.getopt.sh

# Parsing command line options
temp=$(getopt -o "$BUILD_OPTS_SHORT" -l "$BUILD_OPTS_LONG,get-image-path,installer" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-d|--distribution) KALI_DIST="$2"; shift 2; ;;
		-p|--proposed-updates) OPT_pu="1"; shift 1; ;;
		-a|--arch) KALI_ARCH="$2"; shift 2; ;;
		-v|--verbose) VERBOSE="1"; shift 1; ;;
		-s|--salt) shift; ;;
		--installer) IMAGE_TYPE="installer"; shift 1 ;;
		--variant) KALI_VARIANT="$2"; shift 2; ;;
		--version) KALI_VERSION="$2"; shift 2; ;;
		--subdir) TARGET_SUBDIR="$2"; shift 2; ;;
		--get-image-path) ACTION="get-image-path"; shift 1; ;;
		--) shift; break; ;;
		*) echo "ERROR: Invalid command-line option: $1" >&2; exit 1; ;;
        esac
done

# Set default values
KALI_ARCH=${KALI_ARCH:-$HOST_ARCH}
if [ -z "$KALI_VERSION" ]; then
	KALI_VERSION="$(default_version $KALI_DIST)"
fi

# Check parameters
if [ "$HOST_ARCH" != "$KALI_ARCH" ]; then
	case "$HOST_ARCH/$KALI_ARCH" in
		amd64/i386|i386/amd64)
		;;
		*)
			echo "Can't build $KALI_ARCH image on $HOST_ARCH system." >&2
			exit 1
		;;
	esac
fi
if [ ! -d "$(dirname $0)/kali-config/variant-$KALI_VARIANT" ]; then
	echo "ERROR: Unknown variant of Kali configuration: $KALI_VARIANT" >&2
fi

# Build parameters for lb config
KALI_CONFIG_OPTS="--distribution $KALI_DIST -- --variant $KALI_VARIANT"
CODENAME=$KALI_DIST  # for debian-cd
if [ -n "$OPT_pu" ]; then
	KALI_CONFIG_OPTS="$KALI_CONFIG_OPTS --proposed-updates"
	KALI_DIST="$KALI_DIST+pu"
fi

# Set sane PATH (cron seems to lack /sbin/ dirs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Either we use a git checkout of live-build
# export LIVE_BUILD=/srv/cdimage.kali.org/live/live-build

case "$IMAGE_TYPE" in
	live)
		# Or we ensure we have proper version installed
		ver_live_build=$(dpkg-query -f '${Version}' -W live-build)
		if dpkg --compare-versions "$ver_live_build" lt 1:20151215kali1; then
			echo "ERROR: You need live-build (>= 1:20151215kali1), you have $ver_live_build" >&2
			exit 1
		fi

		# Check we have a good debootstrap
		ver_debootstrap=$(dpkg-query -f '${Version}' -W debootstrap)
		if dpkg --compare-versions "$ver_debootstrap" lt "1.0.97"; then
			if ! echo "$ver_debootstrap" | grep -q kali; then
				echo "ERROR: You need debootstrap >= 1.0.97 (or a Kali patched debootstrap). Your current version: $ver_debootstrap" >&2
				exit 1
			fi
		fi
	;;
	installer)
		ver_debian_cd=$(dpkg-query -f '${Version}' -W debian-cd)
		if dpkg --compare-versions "$ver_live_build" lt 3.1.27; then
			echo "ERROR: You need live-build (>= 3.1.27), you have $ver_live_build" >&2
			exit 1
		fi

		if [ ! -d $MIRROR ]; then
			echo "ERROR: You need to have a local Kali mirror and indicate its location in the MIRROR environment variable." >&2
			exit 1
		fi
	;;
esac

# We need root rights at some point
if [ "$(whoami)" != "root" ]; then
	if ! which $SUDO >/dev/null; then
		echo "ERROR: $0 is not run as root and $SUDO is not available" >&2
		exit 1
	fi
else
	SUDO="" # We're already root
fi

if [ "$ACTION" = "get-image-path" ]; then
	echo $(target_image_name $KALI_ARCH)
	exit 0
fi

cd $(dirname $0)
mkdir -p $TARGET_DIR/$TARGET_SUBDIR

IMAGE_NAME="$(image_name $KALI_ARCH)"
set +e
: > build.log

case "$IMAGE_TYPE" in
	live)
		run_and_log $SUDO lb clean --purge
		[ $? -eq 0 ] || failure
		run_and_log lb config -a $KALI_ARCH $KALI_CONFIG_OPTS "$@"
		[ $? -eq 0 ] || failure
		run_and_log $SUDO lb build
		if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
			failure
		fi
	;;
	installer)
		# Configure debian-cd with the runtime parameters
		export CF=$(pwd)/CONF.sh
		. $CF
		export DEBIAN_CD_CONF_SOURCED=true
		export ARCHES=$KALI_ARCH
		export DEBVERSION=$KALI_VERSION
		export CODENAME  # set earlier
		if [ "$KALI_VARIANT" = "netinst" ]; then
		    export DISKTYPE="netinst"
		else
		    export DISKTYPE="DVD"
		fi

		# Setup the required paths
		mkdir -p debian-cd/tmp/apt debian-cd/out debian-cd/basedir
		cp -a /usr/share/debian-cd/* debian-cd/basedir/
		export MIRROR  # set by the user
		export BASEDIR=$(pwd)/debian-cd/basedir
		export TDIR=$(pwd)/debian-cd/tmp
		export APTTMP=$TDIR/apt
		export OUT=$(pwd)/debian-cd/out

		# Configure the task with the packages we want
		mkdir -p $BASEDIR/tasks/$CODENAME
		(
		 echo "#include <debian-installer+kernel>";
		 grep -v '^#' kali-config/variant-$KALI_VARIANT/package-lists/kali.list.chroot
		) >$BASEDIR/tasks/$CODENAME/kali
		export TASK=kali

		run_and_log $BASEDIR/build.sh $KALI_ARCH
		if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
			failure
		fi
	;;
esac

set -e
mv -f $IMAGE_NAME $TARGET_DIR/$(target_image_name $KALI_ARCH)
mv -f build.log $TARGET_DIR/$(target_build_log $KALI_ARCH)
