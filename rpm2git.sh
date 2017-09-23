#!/bin/sh

set -x
set -e

compare_base_source() {
	local sourcedir=$1
	local filename=$2
	local tmpdir=$(mktemp --tmpdir -d)
	local reposrcdir=$tmpdir/repo
	local specsrcdir=$tmpdir/rpm
	local specdir=${filename%.tar*}
	local reposrc=$tmpdir/$specdir.tar

	mkdir $specsrcdir $reposrcdir
	tar xf $sourcedir/$filename -C $specsrcdir

	git archive-all --force-submodules --prefix=$specdir/ $reposrc
	tar xf $reposrc -C $reposrcdir

	if ! diff -x '*.git' -NurpP $specsrcdir $reposrcdir >/dev/null 2>&1;
	then
		echo "${red}GIT source in $reposrcdir and RPM source in $specsrcdir differ${white}"
		rm -rf $tmpdir
		exit 1
	fi

	rm -rf $tmpdir
}

import_source_from_spec() {
	local specfile=$1
	local sourcedir=$2
	local tmpfile=$(mktemp --tmpdir)

	echo "${green}extracting source code for $specfile${white}"

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
	' $tmpfile > ${tmpfile}.list

	mkdir -p dist || :
	while read num filename is_base; do
		if test -n "$is_base"; then
			compare_base_source $sourcedir $filename
		fi
	done < ${tmpfile}.list

	while read num filename is_base; do
		if test -z "$is_base"; then
			cp $sourcedir/$filename dist/
			git add dist/$filename
		fi
	done < ${tmpfile}.list
}

import_patches_from_spec() {
	local specfile=$1
	local sourcedir=$2
	local tmpfile=$(mktemp --tmpdir)

	echo "${green}parsing spec file $specfile${white}"

	awk -v tmpfile=$tmpfile -v sourcedir=$sourcedir '
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
		patches[num, "comment"] = comment;
		patches[num, "command"] = $0;
	}
	$0 ~ PATCH_CMD_RE {
		match($1, PATCH_CMD_RE, a);
		num = a[1];
		patchnums[num] = $0;
	}
	!/^#/ {
		comment = "";
	}

	END {
		for (num in patchnums) {
			filename = patches[num, "filename"];
			comment = patches[num, "comment"];

			file = sourcedir "/" filename;

			mail_header = mail_header_tmp = "";
			message = content = "";
			while ((getline tmp < file) > 0) {
				if (mail_header_tmp == "" && mail_header == "") {
					if (index(tmp, "From ") == 1) {
						mail_header_tmp = tmp;
						continue;
					}
					if (index(tmp, "commit ") == 1) {
						sub("^commit ", "From ", tmp);
						mail_header_tmp = tmp;
						continue;
					}
				}
				if (mail_header_tmp != "") {
					if (tmp != "") {
						sub("^Author: ", "From: ", tmp);
						mail_header_tmp = mail_header_tmp "\n" tmp;
					} else {
						mail_header = mail_header_tmp "\n";
						mail_header_tmp = "";
					}
					continue;
				}

				if (message == "" &&
				    (tmp == "---" || index(tmp, "diff ") == 1)) {
					message = content;
					if (tmp != "---")
						content = "\n" tmp;
					else
						content = "";
					continue;
				}
				content = content "\n" tmp;
			}

			close(file);

			diff = content;
			patch_info = ("\n"\
				"===\n"\
				patches[num, "comment"] \
				patches[num, "command"] "\n"\
				"===\n"\
				patchnums[num] "\n"\
				"===\n"\
				);

			content = mail_header message patch_info "\n\n---" diff;
		        content = content message;

			print "testfile" num;
			print content > "testfile" num;

			print content > tmpfile;
			close(tmpfile);

			if (system("git am --ignore-whitespace " tmpfile))
				break;
		}

		system("rm -f " tmpfile);
	}
	' $specfile

	if test -z "$DEBUG"; then
		rm -f "$tmpfile"
	fi
}

init() {
	red="$(tput setaf 1 || :)"
	green="$(tput setaf 2 || :)"
	white="$(tput setaf 7 || :)"

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

main() {
	local specfile=$1
	local sourcedir=$2

	init

	if test -z "$sourcedir"; then
		sourcedir="$(dirname $specfile)"

		if test "${sourcedir}" != "${sourcedir%/SPECS}"; then
			sourcedir="${sourcedir%/SPECS}/SOURCES"
		fi
	fi

	#import_source_from_spec $specfile $sourcedir
	#return
	import_patches_from_spec $specfile $sourcedir
}

main $@
