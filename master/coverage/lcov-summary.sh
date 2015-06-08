#!/bin/sh

TOP="$(dirname $(realpath $0))"
LOCK_DIR="$TOP/lock.dir"
LOCK_PID="$LOCK_DIR/pid"
GCOV_DIR="$TOP/../public_html/gcov"
MAX_COL=12

# Check lcov option
lcov_opts()
{
    OPTS=""
    if lcov --help | grep -q -- --rc > /dev/null; then
	OPTS="--rc lcov_branch_coverage=1"
    fi
    echo $OPTS
}

lock_summary()
{
    RETRY=30

    # Try to lock
    while ! mkdir "$LOCK_DIR" > /dev/null 2>&1; do
	# Check if lock owner is still live
	if [ ! -r $LOCK_PID ]; then
	    echo "Waiting pid file..."
	    sleep 1
	else
	    PID=$(cat $LOCK_PID)

	    if kill -0 $PID > /dev/null 2>&1; then
		# There is lock owner
		echo "Waiting lock..."
		sleep 10
	    else
		# Stale lock
		rm -rf $LOCK_DIR
	    fi
	fi

	RETRY=$((RETRY - 1))
	if [ $RETRY -eq 0 ]; then
	    # Assume stale lock
	    echo "Lock retry failed"
	    rm -rf $LOCK_DIR
	fi
    done

    echo $$ > $LOCK_DIR/pid
}

unlock_summary()
{
    rm -rf $LOCK_DIR
}

HTML_OUTPUT="$GCOV_DIR/index.html"
HTML_HEADER="$TOP/template-header.html"
HTML_SVG="$TOP/template-svg.html"
HTML_FOOTER="$TOP/template-footer.html"
LCOV_OPTS=$(lcov_opts)

# Check $GCOV_DIR
if [ ! -d $GCOV_DIR ]; then
    echo "No dir: $GCOV_DIR"
    exit 0
fi

lock_summary

cd $GCOV_DIR
ARCHS=$(ls | sort)
for arch in $ARCHS; do
    if [ ! -d "$arch" ]; then
	continue
    fi

    PLOT_DATA="$TOP/$arch.data"

    cd $arch
    # Make summary of coverage
    BUILD_DIRS=$(ls -rt | tail -n $MAX_COL)
    for build in $BUILD_DIRS; do
	# Get "lines", "functions", "branches" percentage
	VALS=$(lcov $LCOV_OPTS --summary $build/tux3.info 2>&1 | \
		   sed -ne 's/.* \([0-9][0-9]*\.[0-9]\)% .*/\1/p')
	set $VALS
	if [ $# -eq 3 ]; then
	    echo "$build $1 $2 $3" >> $PLOT_DATA
	fi
    done

    cd $TOP
    if [ -r $PLOT_DATA ]; then
	IMG_NAME="$arch.svg"
	IMG_FILE="$GCOV_DIR/$IMG_NAME"

	# Output svg
	gnuplot <<EOF
set title "$arch" noenhanced
set term svg
set output "$IMG_FILE"
set ylabel "Coverage" noenhanced
set xtics rotate by -45
set format y "%.1f%%"
set yrange [:100]
set grid

plot "$PLOT_DATA" using 0:2:xticlabels(1) title "lines" with lines, \
     "" using 0:2:2 with labels center offset 0,1 notitle, \
     "$PLOT_DATA" using 0:3:xticlabels(1) title "functions" with lines, \
     "" using 0:3:3 with labels center offset 0,1 notitle, \
     "$PLOT_DATA" using 0:4:xticlabels(1) title "branches" with lines, \
     "" using 0:4:4 with labels center offset 0,1 notitle
EOF

	# Output coverage html template
	echo "<hr/>" >> $HTML_SVG
	echo "<h2>$arch</h2>" >> $HTML_SVG
	echo "<div>" >> $HTML_SVG
	for build in $BUILD_DIRS; do
	    echo "<a href=\"/gcov/$arch/$build\">$build</a>" >> $HTML_SVG
	done
	echo '</div>' >> $HTML_SVG
	echo "<img src=\"$IMG_NAME\">" >> $HTML_SVG
    fi
    rm -f $PLOT_DATA

    cd $GCOV_DIR
done

# Output html
cat $HTML_HEADER $HTML_SVG $HTML_FOOTER > $HTML_OUTPUT
rm -f $HTML_SVG

unlock_summary
