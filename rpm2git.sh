#!/bin/sh

set -e

prepare_spec_file() {
	local specfile=$1
	local newspecfile=$2
	local rpminfofile=$3

	echo "${green}parsing spec file ${specfile}${white}"

	awk --posix '
	BEGIN {
		first_patch_cmd = first_patch = 1;
	}
	/^#|^$/ {
		comment = comment $0 "\n";
		next;
	}
	/^Patch[[:digit:]]+:/ {
		num = $1;
		filename = $NF;
		sub("Patch0*", "", num);
		sub(":", "", num);

		patchdesc[num, "filename"] = filename;
		desc = comment $0;

		gsub("^#", " #", desc);
		gsub("\n#", "\n #", desc);

		patchdesc[num, "desc"] = desc;
		comment = "";
		if (first_patch) {
			print "#PATCHLIST"
			first_patch = 0;
		}
		next;
	}
	/^%patch[[:digit:]]+/ {
		num = $1;
		sub("%patch0*", "", num);

		patchnums[num] = comment $0;
		comment = "";
		if (first_patch_cmd) {
			print "#BUILDLIST"
			first_patch_cmd = 0;
		}
		next;
	}
	!/^#|^$/ {
		if (comment != "") {
			ORS = "";
			print comment;
			ORS = "\n";
			comment = "";
		}
		print
	}
	END {
		print "======RPMINFO======";
		for (num in patchnums) {
			print "===RPMPATCHFILE=== " patchdesc[num, "filename"];
			print "===RPMDESC==="
			print patchdesc[num, "desc"];
			print "===RPMCMD==="
			print patchnums[num]
			print "===RPMEND==="
		}
		print "======RPMINFOEND======";
	}
	' $specfile > $newspecfile

	cp $newspecfile $rpminfofile
	sed -i '1,/======RPMINFO======/d' $rpminfofile
	sed -i   '/======RPMINFO======/,$d' $newspecfile
}

create_mbox_file() {
	local sourcedir=$1
	local rpminfofile=$2
	local newamfile=$3

	local filelist=$(mktemp --tmpdir)
	awk --posix '/===RPMPATCHFILE===/ { print "'$sourcedir'/" $2 }' $rpminfofile > $filelist

	echo "${green}creating mbox to import${white}"

	awk --posix '
	BEGIN {
		rpminfofile = 1;
		num = -1;
	}

	rpminfofile && /^===RPMPATCHFILE===/ {
		num++;
		next;
	}

	rpminfofile && /^======RPMINFOEND======$/ {
		rpminfofile = 0;
		num = -1;
		nextfile;
	}

	rpminfofile {
		patchinfo[num] = patchinfo[num] $0 "\n";
		next;
	}


	FNR == 1 {
		num++;
		mail_header = 1;
		fix_space = find_subject = commitmsg = 0;
		if (num)
			print "";
	}

	mail_header && /^commit / {
		sub("commit", "From");
		fix_space = find_subject = 1;
		$0 = $0 " Mon Sep 17 00:00:00 2001";
	}

	mail_header && /^Author: / {
		sub("Author: ", "From: ");
	}

	mail_header && /^$/ {
		mail_header = 0;
		commitmsg = 1;
	}

	commitmsg && fix_space {
		sub("^[[:space:]]+", "");
	}

	commitmsg && find_subject && /^$/ {
		next;
	}

	commitmsg && find_subject {
		print "Subject: " $0;
		find_subject = 0;
		next;
	}

	commitmsg && /^(diff|---)/ {
		print "";
		ORS="";
		print patchinfo[num];
		ORS="\n";
		commitmsg = 0;
		if ($1 != "---")
			print "---"
	}

	{
		print
	}
	' $rpminfofile $(cat $filelist) > $newamfile
}

compare_base_source() {
	local sourcedir=$1
	local filename=$2
	local specfile=$3
	local tmpdir=$(mktemp --tmpdir -d)
	local reposrcdir=$tmpdir/repo
	local specsrcdir=$tmpdir/rpm
	local specdir=""

	echo "${green}comparing source code GIT vs RPM${white}"

	rpmspec -P $specfile > ${tmpdir}/specfile
	specdir="$(sed -ne '/^%setup.*-n/{s/.*-n *//; s/ .*//; p}' ${tmpdir}/specfile)"

	if test -z "$specdir"; then
		specdir="${filename%.tar*}"
	fi

	local reposrc=$tmpdir/$specdir.tar

	mkdir $specsrcdir $reposrcdir
	tar xf $sourcedir/$filename -C $specsrcdir

	git archive-all --force-submodules --prefix=$specdir/ $reposrc
	tar xf $reposrc -C $reposrcdir

	if ! diff -x '*.git' -NurpP $specsrcdir $reposrcdir -x '.*' >/dev/null 2>&1;
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

	list_source_code_files $specfile > $tmpfile

	mkdir -p dist || :
	while read num filename is_base; do
		if test -n "$is_base"; then
			compare_base_source $sourcedir $filename $specfile
		fi
	done < $tmpfile

	while read num filename is_base; do
		if test -z "$is_base"; then
			cp $sourcedir/$filename dist/
			git add dist/$filename
		fi
	done < $tmpfile

	echo "${green}adding extra source code${white}"

	git commit -F - <<EOF
import sources from $(basename $specfile)

===RPMSKIP===
EOF
}

import_spec() {
	local specfile=$1
	local newspecfile=$2
	local distspecfile=dist/$(basename $specfile)

	mkdir -p dist

	echo "${green}adding spec template${white}"
	cp $newspecfile $distspecfile
	git add $distspecfile
	git commit $distspecfile -F - <<EOF
add $distspecfile

===RPMSKIP===
EOF
}

import_patches() {
	local newamfile=$1

	echo "${green}importing package patches from $newamfile${white}"
	git am --ignore-whitespace $newamfile
}

check_repo() {
	if test -n "$(git show -s | grep '===RPM')"; then
		cat <<EOF
Previously imported RPM found. To update use a temporary branch and then
merge with it:
	git checkout -b tmp origbranch
	$0 $@
	git checkout oldbranch
	git merge tmp --ff-only
EOF
		exit 1
	fi
}

init() {
	. $(dirname $0)/common.sh

	common_init
}

main() {
	init

	local specfile=$1
	local sourcedir=$2

	if test -z "$sourcedir"; then
		sourcedir="$(dirname $specfile)"

		if test "${sourcedir}" != "${sourcedir%/SPECS}"; then
			sourcedir="${sourcedir%/SPECS}/SOURCES"
		fi
	fi

	local newspecfile=$(mktemp --tmpdir)
	local rpminfofile=$(mktemp --tmpdir)
	local newamfile=$(mktemp --tmpdir)

	check_repo $@
	prepare_spec_file $specfile $newspecfile $rpminfofile
	create_mbox_file $sourcedir $rpminfofile $newamfile

	import_source_from_spec $specfile $sourcedir
	import_spec $specfile $newspecfile
	import_patches $newamfile

	echo "${green}DONE${white}"
}

main $@
