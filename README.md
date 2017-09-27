rpm2git2rpm -- silly scripts for converting rpm into git and back
=================================================================

RPM Package Manager was not designed to play nicely with the control version
systems. Yet, most of the packages are build with patches extracted from a
source version control system.

These scripts will help you with keeping your fast-spawning patch-files in a
solid GIT branch.

Installation and requirements
-----------------------------

First, install the `git-archive-all` Python package:

	$ pip install git-archive-all
	...

Then, clone the repo:

	$ git clone https://github.com/paboldin/rpm2git2rpm
	...

And use scripts from there.


Usage
-----

Let's start with a sample: porting RHEL7 QEMU's patches back into repo.

First, download and unpack the source RPM:

	$ mkdir qemu-kvm-rpm
	$ cd qemu-kvm-rpm
	$ curl -O http://vault.centos.org/centos/7.4.1708/updates/Source/SPackages/qemu-kvm-1.5.3-141.el7_4.2.src.rpm
	...
	$ rpm2cpio qemu-kvm*.src.rpm | cpio --extract
	...

Now clone the QEMU GIT repo and mark the appropriate tag version:

	$ cd ..
	$ git clone https://github.com/qemu/qemu
	...
	$ cd qemu
	$ git checkout -b source/1.5.3 v1.5.3
	...

Checkout a new branch and run `rpm2git.sh` on top of it:

	$ git checkout -b source/rhel
	...
	$ ~/rpm2git2rpm/rpm2git.sh ../qemu-kvm-rpm/qemu-kvm.spec
	...

This first compares base package sources, then copies all the package sources
such as scripts into a `dist/` library under branch and finally applies all
the package patches as GIT commits while doing the bookkeeping.

You can now apply your own patches on top of that, just remember to mimic the
bookkeeping info. For instance, let's change version output to a
[BolgenOS](http://www.bolgenos.su/index_en.html)
one:

```diff
diff --git a/vl.c b/vl.c
index 7c34b7c..3270347 100644
--- a/vl.c
+++ b/vl.c
@@ -2001,7 +2001,7 @@ static void main_loop(void)
 
 static void version(void)
 {
-    printf("QEMU emulator version " QEMU_VERSION QEMU_PKGVERSION ", Copyright (c) 2003-2008 Fabrice Bellard\n");
+    printf("BolgenOS emulator version " QEMU_VERSION QEMU_PKGVERSION ", Copyright (c) 2003-2008 Denis Popov\n");
 }
 
 static void print_rh_warning(void)
```

Save the above snippet as a patch file and apply it:

	$ patch -p1 < bolgen-os-emulator-copyright.patch
	...

Now commit the changes and don't forget to add the required meta-data:

	$ git commit -a -F - <<EOF
	correct copyright by Denis Popov

	===RPMDESC===
	# Denis Popov wrote all the software in the world
	Patch10001: denis-popov-wrote-it-all.patch
	===RPMCMD===
	# Fix the Bug -- can't be written by anybody but Denis Popov
	%patch10001 -p 1
	===RPMEND===
	EOF
	...

Note the `RPMDESC` and `RPMCMD` metadata sections.

The `RPMDESC` metadata contains the part of the RPM spec file that will be
appended to the place where all the patches are described.

The `RPMCMD` metadata contains appropriate build instruction for the patch.

Let's now prepare and build the source RPM for our QEMU KVM version:

	$ ~/rpm2git2rpm/git2rpm.sh source/1.5.3 output
	...
	Use:
	rpmbuild -bs --define '_topdir output/' output//SPECS/qemu-kvm.spec
	To build SRPM.
	$ rpmbuild -bs --define '_topdir output/' output//SPECS/qemu-kvm.spec
	Wrote: output/SRPMS/qemu-kvm-1.5.3-141.2.src.rpm

Congratulations on your first patch applied via rpm2git2rpm!
