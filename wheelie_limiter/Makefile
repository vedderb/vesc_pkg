VESC_TOOL ?= vesc_tool

all: wheelie_limiter.vescpkg

wheelie_limiter.vescpkg:
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

clean:
	rm -f wheelie_limiter.vescpkg

.PHONY: all clean
