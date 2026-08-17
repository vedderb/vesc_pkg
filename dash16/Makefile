VESC_TOOL ?= vesc_tool

all: dash16.vescpkg dash16_test.vescpkg

dash16.vescpkg: README_Disp-gen.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:dash16' --testPkgDesc 'vesc:test'
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_test.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:dash16' --testPkgDesc 'vesc:test'

VERSION=`cat version`

README_Disp-gen.md: README_Disp.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

clean:
	rm -f dash16.vescpkg
	rm -f dash16_test.vescpkg
	rm -f README_Disp-gen.md
	rm -f ui.qml

.PHONY: all clean
