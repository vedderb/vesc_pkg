VESC_TOOL ?= vesc_tool

all: vl_bike_39p_stm.vescpkg vl_bike_39p_esp.vescpkg

vl_bike_39p_stm.vescpkg: pkgdesc_stm.qml README_stm.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_stm.qml --testPkgDesc 'custom:vbms16:harmony' --testPkgDesc 'vesc:maxim 120' --testPkgDesc 'vesc:pronto'
	
vl_bike_39p_esp.vescpkg: pkgdesc_esp.qml README_esp.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc_esp.qml --testPkgDesc 'custom:vbms16:harmony' --testPkgDesc 'vesc:maxim 120' --testPkgDesc 'custom:str365 io'

VERSION=`cat version`

README_stm.md: README_stm-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@
	
README_esp.md: README_esp-in.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

clean:
	rm -f vl_bike_39p_stm.vescpkg vl_bike_39p_esp.vescpkg README_stm.md README_esp.md

.PHONY: all clean
