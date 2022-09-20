# VESC Packages

This repository contains packages that show up in the package store in VESC Tool. A VESC Package consists of:

* A description, which can include formatted text and images.
* An optional LispBM-script with optional includes.
	- The includes can also contain one or more compiled C libraries.
* An optional QML-file.

Packages can be pulled and updated from VESC Tool on demand, so their development does not have to be synchronized with the VESC Tool development. This is an advantage for package developers and maintainers as they can control how and when they make their releases. There is also no need for users to update their VESC Tool and firmware, they can just refresh the package store in VESC Tool and reinstall the updated package.

## How to include your package

To include your package in VESC Tool you can make a pull request to this repository. Your pull request should include:

* A description of what your package does.
* Instructions on how to use it.
* If it contains compiled C libraries their source code must be included in the pull request under the GPL license (see the examples).

### Notes

* Make sure that you build a VESC Package file (\*.vescpkg) in the main directory of your package (e.g. euc/euc.vescpkg)
* Make sure to add your package to res_all.qrc in the root of the repository.
* Test your .vescpkg-file before making a pull request!