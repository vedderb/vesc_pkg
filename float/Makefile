VESC_TOOL ?= vesc_tool

all: clean float.vescpkg

float.vescpkg: float README-pkg.md ui.qml
	$(VESC_TOOL) --buildPkg "float.vescpkg:float.lisp:ui.qml:0:README-pkg.md:Float"

float:
	$(MAKE) -C $@

VERSION=`grep APPCONF_FLOAT_VERSION float/conf/settings.xml -A10 | grep valDouble | tr -dc '[.[:digit:]]'`

README-pkg.md: README.md
	cp README.md README-pkg.md
	echo "- Version: ${VERSION}" >> README-pkg.md
	echo "- Build Date: `date --rfc-3339=seconds`" >> README-pkg.md
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> README-pkg.md

ui.qml: ui.qml.in
	cat ui.qml.in | sed "s/{{VERSION}}/${VERSION}/g" > ui.qml

clean:
	rm -f float.vescpkg README-pkg.md ui.qml
	$(MAKE) -C float clean

.PHONY: all clean float
