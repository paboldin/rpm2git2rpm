#!/bin/sh

common_init() {
	red="$(tput setaf 1 || :)"
	green="$(tput setaf 2 || :)"
	white="$(tput setaf 7 || :)"
	scriptname="$0"

	set +e
	git archive-all >/dev/null 2>&1
	rv=$?
	if test $rv -ne 2; then
		echo "git archive-all required, install it with:"
		echo "pip install archive-all"
		exit 1
	fi
	set -e
}

list_source_code_files() {
	local specfile=$1
	local tmpfile=$(mktemp --tmpdir)

	rpmspec -P $specfile > $tmpfile
	awk '
	BEGIN {
		SOURCE_RE = "^Source([[:digit:]]+)";
	}
	$0 ~ SOURCE_RE {
		match($1, SOURCE_RE, a);
		num = a[1];
		filename = $NF;
		sources[num] = filename;
	}

	END {
		url = -1;
		for (num in sources) {
			filename = sources[num];
			if (index(filename, "/") != 0) {
				split(filename, a, "/");
				filename = a[length(a)];
				url = num;
			}
			print num, filename, url == num ? "BASE" : "";
		}
	}
	' $tmpfile

	rm -f $tmpfile
}
