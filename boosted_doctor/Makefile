VESC_TOOL ?= vesc_tool

all: boosted_doctor.vescpkg

boosted_doctor.vescpkg:
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

clean:
	rm -f boosted_doctor.vescpkg

.PHONY: all clean
