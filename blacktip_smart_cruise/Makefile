VESC_TOOL ?= vesc_tool

all: blacktip_smart_cruise.vescpkg

blacktip_smart_cruise.vescpkg: pkgdesc.qml README.md ui.qml blacktip_smart_cruise.lisp
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'vesc:test'

test:
	@echo "No tests defined"

clean:
	rm -f blacktip_smart_cruise.vescpkg

.PHONY: all test clean
