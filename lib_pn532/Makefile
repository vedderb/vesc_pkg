VESC_TOOL ?= vesc_tool

all: pn532.vescpkg

pn532.vescpkg:
	$(VESC_TOOL) --buildPkg "pn532.vescpkg:pn532.lisp::0:README.md:PN532"

clean:
	rm -f pn532.vescpkg

.PHONY: all clean
