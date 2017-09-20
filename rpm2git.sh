#!/bin/sh -xe

parse_spec() {
	local specfile=$1

	awk '
	BEGIN {
		PATCH_RE = "^Patch([[:digit:]]+)";
		PATCH_CMD_RE = "^%patch([[:digit:]]+)";
	}
	/^#/ {
		comment = comment $0 "\n";
	}
	$0 ~ PATCH_RE {
		match($1, PATCH_RE, a);
		num = a[1];
		filename = $NF;
		patches[num, "filename"] = filename;
		gsub("# |\n$|#Patch.*\n|\n\n", "", comment);
		patches[num, "comment"] = comment;
		comment = "";
	}
	$0 ~ PATCH_CMD_RE {
		match($1, PATCH_CMD_RE, a);
		num = a[1];
		patchnums[num] = 1;
	}
	!/^#/ {
		if (comment) {
			comment = "";
		}
	}

	END {
		prevcomment = "";
		print "tmpfile=$(mktemp --tmpdir)"
		for (num in patchnums) {
			filename = patches[num, "filename"];
			comment = patches[num, "comment"];

			if (!comment)
				comment = prevcomment;

			print "git apply --cached $SOURCES/" filename;
			print "cat >$tmpfile <<'"'"'EOF'"'"'"
			print comment
			print ""
			print "patch-id: " num
			print "patch-filename: " filename
			print "==="
			print "EOF"
			print "\n";
			print "sed \"/^---\\$/,\\$d\" $SOURCES/" filename " >> $tmpfile"
			print "git commit -F $tmpfile"
			print "\n\n";

			prevcomment = comment;
		}
	}
	' $specfile
}

main() {
	local specfile=$1
	local sourcedir=$2

	if test -z "$sourcedir"; then
		sourcedir="$(dirname $specfile)"
	fi

	local tmpfile=$(mktemp --tmpdir)
	local green="$(tput setaf 2 || :)"
	local white="$(tput setaf 7 || :)"
	echo "${green}parsing spec file $specfile${white}"
	parse_spec $specfile > $tmpfile

	echo "${green}executing file $tmpfile${white}"
	SOURCES="$sourcedir" sh -xe $tmpfile
}

main $@
