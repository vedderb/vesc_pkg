VESC_TOOL ?= vesc_tool

all: nau7802.vescpkg

nau7802.vescpkg:
	$(VESC_TOOL) --buildPkg "nau7802.vescpkg:nau7802.lisp::0:README.md:NAU7802 Driver"

clean:
	rm -f nau7802.vescpkg

.PHONY: all clean
