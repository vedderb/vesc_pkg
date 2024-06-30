VESC_TOOL ?= vesc_tool

all: vdisp.vescpkg vdisp_esc.vescpkg

vdisp.vescpkg: README_Disp-gen.md README_ESC-gen.md
	$(VESC_TOOL) --buildPkg "vdisp.vescpkg:main.lisp::0:README_Disp-gen.md:VDisp"
	$(VESC_TOOL) --buildPkg "vdisp_esc.vescpkg:main-esc.lisp::0:README_ESC-gen.md:VDisp ESC"

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

clean:
	rm -f vdisp.vescpkg
	rm -f vdisp_esc.vescpkg
	rm -f README_Disp-gen.md
	rm -f README_ESC-gen.md

.PHONY: all clean
