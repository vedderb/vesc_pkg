VESC_TOOL ?= vesc_tool

all: vl_link_status.vescpkg

vl_link_status.vescpkg: pkgdesc.qml README.md ui.qml code.lbm
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vl link'

VERSION=`cat version`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date '+%Y-%m-%d %H:%M:%S %z'`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD 2>/dev/null || echo local`" >> $@

clean:
	rm -f vl_link_status.vescpkg README.md

.PHONY: all clean
