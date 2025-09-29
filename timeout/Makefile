VESC_TOOL ?= vesc_tool
OLDVT ?= 0

all: timeout.vescpkg

timeout.vescpkg: timeout.lisp README.md pkgdesc.qml
ifeq ($(OLDVT), 1)
	$(VESC_TOOL) --buildPkg "timeout.vescpkg:timeout.lisp::0:README.md:Remote Timeout"
else
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'vesc:test'
endif

clean:
	rm -f timeout.vescpkg

.PHONY: all clean


