#!/bin/sh

set -x
set -e

extract_patches() {
	local base=$1
	local end=${2-HEAD}

	git format-patch --output-directory=$outputdir ${base}...${end} > \
		$outputdir/list
	awk -v tmpdir=$tmpsrcdir -v specparts=$specparts '
	{
		file = $0;
		newheader = ""

		patchinfoval = "";
		delete patchinfo;

		while ((getline tmp < file) > 0) {
			if (match(tmp, "^===([A-Z]+)===$", a)) {
				patchinfoval = a[1];
				if (patchinfoval == "RPMEND")
					patchinfoval = "";
				else
					patchinfo[patchinfoval] = "";
				continue;
			}
			if (patchinfoval != "") {
				patchinfo[patchinfoval] = \
					patchinfo[patchinfoval] tmp "\n";
				continue;
			}
			newheader = newheader tmp "\n";
			if (tmp == "---")
				break;
		}

		if ("RPMSKIP" in patchinfo)
			next;

		patchdesc = patchinfo["RPMDESC"];
		patchcmd = patchinfo["RPMCMD"];

		if (patchdesc == "" || patchcmd == "" ||
		    !match(patchdesc, ".*Patch[[:digit:]]+: ([^[:space:]]+)", a)) {
			ORS = "\n";
			print "Cannot parse RPM spec info for " file > "/dev/stderr";
			print "Please refer to README.md" > "/dev/stderr";
			exit 1
		}

		newfile = tmpdir "/" a[1];

		save_rs = RS
		RS = "^$"

		getline tmp < file
		print newheader > newfile;
		print tmp > newfile;

		print newfile;

		RS = save_rs
		close(file)
		close(newfile);

		ORS = "";
		print patchdesc > specparts ".list";
		print patchcmd > specparts ".build";
		ORS = "\n";
	}

	END {
		close(specparts ".list")
		close(specparts ".build")
	}
	' $outputdir/list
	xargs rm < $outputdir/list
	rm -f $outputdir/list
}

copy_sources() {
	local base=$1
	local spec=$2
	local tmpfile=$(mktemp --tmpdir)

	list_source_code_files $spec > $tmpfile

	local currentbranch=$(git rev-parse --abbrev-ref HEAD)
	if test -z "$currentbranch"; then
		echo "Cannot find current branch" >&2
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
		echo "git archive-all failed with $rv" >&2
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

	cp "$spec" "$tmpspecdir"

	spec="$outputdir/SPECS/$(basename $spec)"
	sed -i '/#PATCHLIST/{ r '$specparts'.list
			     d }
		/#BUILDLIST/{ r '$specparts'.build
			     d }' $spec
	echo $spec

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

main() {
	local base=$1
	local output=$2
	local spec=$3
	local end=$4

	init $output

	if test -z "$spec"; then
		spec=$(echo dist/*.spec);
	fi

	copy_sources $base $spec
	extract_patches $base $end
	interpolate_spec $spec
}

main $@
