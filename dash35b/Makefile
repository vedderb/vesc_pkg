VESC_TOOL ?= vesc_tool

all: dash35b.vescpkg dash35b_esc.vescpkg

dash35b.vescpkg: README_Disp-gen.md README_ESC-gen.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_esc.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:vdisp 900' --testPkgDesc 'vesc:test'
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'custom:vdisp 900' --testPkgDesc 'vesc:test'

VERSION=`cat version`
VERSION_ESC=`cat version_esc`

README_Disp-gen.md: README_Disp.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

README_ESC-gen.md: README_ESC.md version_esc
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION_ESC}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

clean:
	rm -f dash35b.vescpkg
	rm -f dash35b_esc.vescpkg
	rm -f README_Disp-gen.md
	rm -f README_ESC-gen.md
	rm -f ui.qml

.PHONY: all clean
