#!/bin/sh -xe

parse_repo() {
	local base=$1
	local end=${2-HEAD}

	tmpdir="$(mktemp --tmpdir --directory)/"
	tmpspec="$(mktemp --tmpdir)"

	git format-patch --output-directory=$tmpdir ${base}...${end} > \
		$tmpdir/list
	awk -v tmpdir=$tmpdir -v tmpspec=$tmpspec '
	{
		file = $0;
		newfilename = ""
		patchnum = ""
		comment = ""
		while ((getline tmp < file) > 0) {
			if (tmp == "" && comment == "") {
				getline comment < file
				continue
			}
			if (index(tmp, "patch-") == 1) {
				patsplit(tmp, a);
				if (a[1] == "patch-filename:")
					newfilename = a[2]
				else if (a[1] == "patch-id:")
					patchnum = a[2]
			}
			if (tmp == "===")
				break;
		}
		save_rs = RS
		RS = "^$"

		getline tmp < file
		print tmp > tmpdir newfilename
		RS = save_rs
		close(file)
		close(tmpdir newfilename)

		print "# " comment > tmpspec ".list"
		print "Patch" patchnum ": " newfilename > tmpspec ".list"

		print "%patch" patchnum " -p1" > tmpspec ".build"
	}

	END {
		close(tmpspec ".list")
		close(tmpspec ".build")
	}
	' $tmpdir/list
	xargs rm < $tmpdir/list
}

main() {
	local base=$1
	local spec=$2
	local end=$3

	parse_repo $base $end

	cp $spec $tmpdir
	spec=$tmpdir/$(basename $spec)
	sed -i '/PATCHLIST/{ r '$tmpspec'.list
			     d }
		/BUILDLIST/{ r '$tmpspec'.build
			     d }' $spec

	echo $spec
}

main $@
