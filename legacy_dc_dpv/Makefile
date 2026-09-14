VESC_TOOL ?= vesc_tool

all: legacy_dc_dpv.vescpkg

legacy_dc_dpv.vescpkg: legacy_dc_dpv.lisp ui.qml pkgdesc.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

legacy_dc_dpv: legacy_dc_dpv.vescpkg
	# Nothing

clean:
	rm legacy_dc_dpv.vescpkg

.PHONY: all clean legacy_dc_dpv"
