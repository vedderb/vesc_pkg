VESC_TOOL ?= vesc_tool

all: vbms_harmony16.vescpkg

vbms_harmony16.vescpkg: pkgdesc.qml README.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms16:harmony' --testPkgDesc 'vesc:vbms16' --testPkgDesc 'custom:vbms16'

VERSION=`cat version`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f vbms_harmony16.vescpkg README.md

.PHONY: all clean
