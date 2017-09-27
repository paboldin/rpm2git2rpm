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
	awk --posix '
	/^Source[[:digit:]]+:/ {
		num = $1;
		sub("Source", "", num);
		sub(":", "", num);

		filename = url = $NF;
		sub(".*/", "", filename);

		print num, filename, filename != url ? "BASE" : "";
	}
	' $tmpfile

	rm -f $tmpfile
}
