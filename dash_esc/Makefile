VESC_TOOL ?= vesc_tool

all: dash_esc.vescpkg

dash_esc.vescpkg: README-gen.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:dash16' --testPkgDesc 'vesc:test'

VERSION=`cat version`

README-gen.md: README.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f dash_esc.vescpkg
	rm -f README-gen.md

.PHONY: all clean
