VESC_TOOL ?= vesc_tool

all: vbms32_micro.vescpkg

vbms32_micro.vescpkg: pkgdesc.qml README.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:vbms32'

VERSION=`cat version`
BUILD_DATE=`date --rfc-3339=seconds`
GIT_COMMIT=`git rev-parse --short HEAD`

README.md: README-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: ${BUILD_DATE}" >> $@
	echo "- Git Commit: #${GIT_COMMIT}" >> $@

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" | sed "s/{{BUILD_DATE}}/${BUILD_DATE}/g" | sed "s/{{GIT_COMMIT}}/#${GIT_COMMIT}/g" > ui.qml

clean:
	rm -f vbms32_micro.vescpkg README.md ui.qml

.PHONY: all clean
