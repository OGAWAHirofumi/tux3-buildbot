#!/bin/sh

PATH=$PATH:/devel/works/qemu/usr/bin

KVM=qemu-system-x86_64
PID_FILE=kvm-pid.pid
MON_FIFO=kvm-pipe
SERIAL=kvm-serial
CONFIG=kvm-config

cleanup()
{
    rm -f $PID_FILE $MON_FIFO.* $SERIAL $CONFIG
}

ssh_opts()
{
    . "./$CONFIG"

    echo -o "User=root" \
	-o "Port=$port" \
	-o "IdentityFile=$ssh_key" \
	-o "UserKnownHostsFile=/dev/null" \
	-o "StrictHostKeyChecking=no" \
	-o "BatchMode=yes" \
	-o "LogLevel=ERROR"
}

cmd_ssh()
{
    ssh $(ssh_opts) "localhost" "$@"
}

cmd_scp()
{
    scp $(ssh_opts) "$@"
}

wait_ssh()
{
    for i in $(seq 36); do
	ssh $(ssh_opts) -o "ConnectTimeout=5" "localhost" "/bin/true"
	if [ $? != 255 ]; then
	    return $?
	fi

	sleep 5
    done

    return 255
}

wait_kvm_prompt()
{
    for i in $(seq 600); do
	if ! pkill --signal 0 --pidfile "$PID_FILE" 2> /dev/null; then
	    # kvm seems died
	    return 1
	fi

	# Find prompt
	if dd if=$MON_FIFO.out bs=1M iflag=nonblock 2> /dev/null \
	    | grep '(qemu)' > /dev/null; then
	    return 0
	fi

	sleep 1
    done

    # timeout
    return 255
}

cmd_serial()
{
    if [ -r "$SERIAL" ]; then
	cat "$SERIAL"
    fi
}

cmd_dump()
{
    vmcore="$1"
    if [ "$vmcore" = "" ]; then
	vmcore="vmcore"
    fi

    if pkill --signal 0 --pidfile "$PID_FILE" 2> /dev/null; then
	rm -f $vmcore

	echo "dump-guest-memory $(pwd)/$vmcore" > $MON_FIFO.in
	if ! wait_kvm_prompt; then
	    echo "Couldn't find (qemu) prompt"
	    cmd_quit
	    exit 1
	fi
    fi
}

# bb-kvm.sh run <port> <sshkey> [kvm options]
cmd_run()
{
    port="$1"
    ssh_key="$2"
    shift 2

    if [ -r "$PID_FILE" ]; then
	if pkill --signal 0 --pidfile "$PID_FILE" 2> /dev/null; then
	    echo "Already running: '$PID_FILE'"
	    exit 1
	fi

	echo "---------------------- [Start OLD serial] ----------------------"
	cmd_serial
	echo "---------------------- [End OLD serial] ------------------------"
    fi

    if echo $port | grep -v '[0-9]' > /dev/null; then
	echo "Invalid port number: '$port'"
	exit 1
    fi
    if [ ! -r "$ssh_key" ]; then
	echo "Invalid ssh key: '$ssh_key'"
	exit 1
    fi

    cleanup

    SNAPSHOT_OPT="-snapshot"
    if [ "$NO_SNAPSHOT" = 1 ]; then
	SNAPSHOT_OPT=""
    fi
    
    echo "port=$port" >> $CONFIG
    echo "ssh_key=$ssh_key" >> $CONFIG

    mkfifo -m 600 $MON_FIFO.in $MON_FIFO.out

    $KVM \
	-enable-kvm \
	$SNAPSHOT_OPT \
	-display none \
	-serial "file:$SERIAL" \
	-monitor "pipe:$MON_FIFO" \
	-daemonize \
	-pidfile "$PID_FILE" \
	"$@"

    if [ $? != 0 ]; then
	cleanup
	exit 1
    fi
    if ! wait_kvm_prompt; then
	echo "Couldn't find (qemu) prompt"
	cmd_quit
	exit 1
    fi

    # Add port forward to ssh
    echo "hostfwd_add tcp::$port-:22" > $MON_FIFO.in
    if ! wait_kvm_prompt; then
	echo "Couldn't set hostfwd"
	cmd_quit
	exit 1
    fi

    # Wait ssh
    if ! wait_ssh; then
	cmd_quit
	exit 1
    fi
}

# variant of run command without snapshot
cmd_mod()
{
    NO_SNAPSHOT=1 cmd_run "$@"
}

cmd_quit()
{
    opt="$1"
    shift

    if pkill --signal 0 --pidfile "$PID_FILE" 2> /dev/null; then
	case "$opt" in
	    dump_serial)
		vmcore="$1"
		shift

		cmd_serial
		cmd_dump "$vmcore"
		;;
	    serial)
		cmd_serial
		;;
	esac

	echo "quit" > $MON_FIFO.in
    fi
    cleanup
}

cmd="$1"
shift

case "$cmd" in
    run|mod|ssh|scp|serial|dump|quit)
	"cmd_$cmd" "$@"
	;;
    *)
	echo "Unknown cmd: $cmd"
	exit 1
	;;
esac
