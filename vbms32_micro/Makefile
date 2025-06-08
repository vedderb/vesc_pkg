VESC_TOOL ?= ~/vesc_tool_test_linux

all: vbms32_micro.vescpkg

vbms32_micro.vescpkg: pkgdesc.qml README.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:vbms32'

VERSION=`cat version`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

clean:
	rm -f vbms32_micro.vescpkg README.md ui.qml

.PHONY: all clean
