VESC_TOOL ?= vesc_tool

all: vbms32.vescpkg

vbms32.vescpkg: pkgdesc.qml README.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:vbms32' --testPkgDesc 'custom:vbms32:micro'


VERSION=`cat version`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f vbms32.vescpkg README.md

.PHONY: all clean
