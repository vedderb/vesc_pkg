VESC_TOOL ?= vesc_tool

all: clean tnt.vescpkg

tnt.vescpkg: tnt README-pkg.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'vesc:test'

tnt:
	$(MAKE) -C $@

VERSION=`grep APPCONF_TNT_VERSION tnt/conf/settings.xml -A10 | grep valDouble | tr -dc '[.[:digit:]]'`

README-pkg.md: README.md
	cp README.md README-pkg.md
	echo "- Version: ${VERSION}" >> README-pkg.md
	echo "- Build Date: `date --rfc-3339=seconds`" >> README-pkg.md
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> README-pkg.md

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

clean:
	rm -f tnt.vescpkg README-pkg.md ui.qml
	$(MAKE) -C tnt clean

.PHONY: all clean tnt
