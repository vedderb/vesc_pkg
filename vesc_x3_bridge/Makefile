VESC_TOOL ?= vesc_tool

all: vesc_x3_bridge_esp.vescpkg vesc_x3_bridge_stm.vescpkg

vesc_x3_bridge_esp.vescpkg: pkgdesc_esp.qml README_esp.md code_esp.lisp ui_esp.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_esp.qml

vesc_x3_bridge_stm.vescpkg: pkgdesc_stm.qml README_stm.md code_stm.lisp
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_stm.qml

VERSION=`cat version`

README_esp.md: README_esp-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

README_stm.md: README_stm-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f vesc_x3_bridge_esp.vescpkg vesc_x3_bridge_stm.vescpkg README_esp.md README_stm.md

.PHONY: all clean
