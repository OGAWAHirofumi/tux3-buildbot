#!/bin/sh
#
# Run post process (remove old outputs, fix permissions, etc.)
#

THIS_SCRIPT=$(realpath "$0")
TOP=$(dirname "$THIS_SCRIPT")

. "$TOP/common.sh"

# Keep $NR_KEEP number of data
NR_KEEP=20

# Change permission file=644, dir=755
fixup_perm()
{
    FIXUP_DIR="$1"

    if [ -d "$FIXUP_DIR" ]; then
	find "$FIXUP_DIR" -type d -print0 | xargs -0 chmod 755
	find "$FIXUP_DIR" -type f -print0 | xargs -0 chmod 644
    fi
}

# Remove old entries except recent $NR_KEEP entries
cleanup()
{
    CLEANUP_DIR="$1"

    if [ -d "$CLEANUP_DIR" ]; then
	for target in $(ls -rt "$CLEANUP_DIR" | head -n -$NR_KEEP); do
	    echo "Remove: $CLEANUP_DIR/$target"
	    rm -rf "$CLEANUP_DIR/$target"
	done
    fi
}

cleanup_in_arches()
{
    CLEAN_ARCH_DIR="$1"

    if [ -d "$CLEAN_ARCH_DIR" ]; then
	cd "$CLEAN_ARCH_DIR"
	ARCHS=$(ls | sort)
	for arch in $ARCHS; do
	    if [ ! -d "$arch" ]; then
		continue
	    fi

	    cleanup "$CLEAN_ARCH_DIR/$arch"
	done
    fi
}

lock_scripts

#
# Remove old entries to prevent ENOSPC
#
cleanup_in_arches "$GCOV_DIR"
cleanup_in_arches "$BIN_DIR"

#
# Change permissions to allow to access from HTTP server
#
fixup_perm "$WWW_DIR"

unlock_scripts
