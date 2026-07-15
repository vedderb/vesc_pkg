VESC_TOOL ?= vesc_tool

all: VESCXPRESS2X3Bridge.vescpkg

VESCXPRESS2X3Bridge.vescpkg: pkgdesc.qml README.md main.lisp main-settings.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

VERSION=`cat version`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f VESCXPRESS2X3Bridge.vescpkg README.md

.PHONY: all clean
