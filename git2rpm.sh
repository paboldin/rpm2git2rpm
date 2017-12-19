#!/bin/sh

#set -x
set -e

extract_patches() {
	local base=$1
	local end=${2-HEAD}

	echo "${green}copying patches${white}"

	git format-patch --output-directory=$outputdir \
		--no-numbered \
		${base}...${end} > \
		$outputdir/list

	xargs grep -H '^Patch[0-9]\+: ' < $outputdir/list > $outputdir/patches
	awk -v tmpsrcdir=$tmpsrcdir '
	BEGIN {
		npatch = 0;
	}
	{
		patchnum = $1;
		gsub(".*Patch", "", patchnum);
		gsub(":.*", "", patchnum);

		gitname = $1;
		gsub(":Patch.*", "", gitname);

		if (patchfiles[patchnum, "git"] == "")
			patchnums[npatch++] = patchnum;

		patchfiles[patchnum, "git"] = gitname;
		patchfiles[patchnum, "rpm"] = $2;
	}
	END {
		for (i = 0; i < npatch; i++) {
			patchnum = patchnums[i];
			gitname = patchfiles[patchnum, "git"];
			rpmname = patchfiles[patchnum, "rpm"];
			print "mv " gitname " " tmpsrcdir rpmname;
		}
	}' $outputdir/patches > $outputdir/renaming
	sh -xe $outputdir/renaming

	awk '{ print $NF; }' $outputdir/renaming > $outputdir/list

	xargs sed -n '/^===RPMDESC===$/,/^===RPM/p' < $outputdir/list > $specparts.list
	xargs sed -n '/^===RPMCMD===$/,/^===RPM/p' < $outputdir/list > $specparts.build
	xargs sed -i '/^===RPM/,/^===RPMEND===$/d' < $outputdir/list

	sed -i -e '/^===RPM/d' -e 's/^ #/#/' $specparts.list $specparts.build

	rm -f $outputdir/*.patch $outputdir/list $outputdir/renaming
}

copy_sources() {
	local base=$1
	local spec=$2
	local tmpfile=$(mktemp --tmpdir)

	echo "${green}copying sources${white}"

	list_source_code_files $spec > $tmpfile

	local currentbranch=$(git rev-parse --abbrev-ref HEAD)
	if test -z "$currentbranch"; then
		echo "${red}Cannot find current branch${white}" >&2
		exit 1
	fi

	set +e

	git checkout $base
	while read num filename is_base; do
		if test -n "$is_base"; then
			local srcdir=${filename%.tar*}
			git archive-all --force-submodules --prefix=$srcdir/ $tmpsrcdir/$filename
			rv=$?
			break;
		fi
	done < $tmpfile
	git checkout $currentbranch
	set -e

	if test $rv -ne 0; then
		echo "${red}git archive-all failed with $rv${white}" >&2
		exit $rv;
	fi

	while read num filename is_base; do
		if test -z "$is_base"; then
			cp dist/$filename $tmpsrcdir/$filename
		fi
	done < $tmpfile
}

interpolate_spec() {
	local spec=$1

	echo "${green}preparing spec${white}"
	cp "$spec" "$tmpspecdir"

	spec="$outputdir/SPECS/$(basename $spec)"
	sed -i '/#PATCHLIST/{ r '$specparts'.list
			     d }
		/#BUILDLIST/{ r '$specparts'.build
			     d }' $spec
	rm -f ${specparts}.list ${specparts}.build
	echo "RPM spec is in $spec"
	echo "Use:"
	echo "rpmbuild -bs --define '_topdir $outputdir' $spec"
	echo "To build SRPM"
}

init() {
	. $(dirname $0)/common.sh

	common_init

	outputdir=$1

	if test -z "$outputdir"; then
		outputdir="$(mktemp --tmpdir --directory)/"
	fi
	specparts="$outputdir/specparts"
	tmpsrcdir="$outputdir/SOURCES/"
	tmpspecdir="$outputdir/SPECS/"

	mkdir -p $tmpsrcdir $tmpspecdir
}

usage() {
	local scriptname=$(basename $0)
	echo "\
$scriptname -- export git repo into rpmbuild'able dir

Usage: $scriptname BASEREF OUTPUTDIR [SPECTEMPLATE] [LASTREF]
	BASEREF -- export starts from this base ref,
	OUTPUTDIR -- directory with rpmbuild'able output, will be created
		     if not existing,
	[SPECTEMPLATE] -- template with spec file; fefault is dist/*.spec,
	[LASTREF] -- export patches until this ref.

See README.md for details."
}


main() {
	local base=$1
	local output=$2
	local spec=$3
	local end=$4

	if test $# -lt 2; then
		usage
		exit
	fi

	init $output

	if test -z "$spec"; then
		spec=$(echo dist/*.spec);
	fi

	copy_sources $base $spec
	extract_patches $base $end
	interpolate_spec $spec
}

main $@
