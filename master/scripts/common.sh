#
# provide lock
#

COMMON_SCRIPT=$(realpath "$0")
COMMON_TOP=$(dirname "$COMMON_SCRIPT")
LOCK_DIR="$COMMON_TOP/lock.dir"
LOCK_PID="$LOCK_DIR/pid"

WWW_DIR=$(realpath "$COMMON_TOP/../../www")
GCOV_DIR="$WWW_DIR/gcov"
BIN_DIR="$WWW_DIR/binaries"

lock_scripts()
{
    RETRY=30

    # Try to lock
    while ! mkdir "$LOCK_DIR" > /dev/null 2>&1; do
	# Check if lock owner is still live
	if [ ! -r "$LOCK_PID" ]; then
	    echo "Waiting pid file..."
	    sleep 1
	else
	    PID=$(cat "$LOCK_PID")

	    if kill -0 "$PID" > /dev/null 2>&1; then
		# There is lock owner
		echo "Waiting lock..."
		sleep 10
	    else
		# Stale lock
		rm -rf "$LOCK_DIR"
	    fi
	fi

	RETRY=$((RETRY - 1))
	if [ $RETRY -eq 0 ]; then
	    # Assume stale lock
	    echo "Lock retry failed"
	    rm -rf "$LOCK_DIR"
	fi
    done

    echo $$ > "$LOCK_PID"
}

unlock_scripts()
{
    rm -rf "$LOCK_DIR"
}
