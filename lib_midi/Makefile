VESC_TOOL ?= vesc_tool

all: midi.vescpkg

midi.vescpkg: midi
	$(VESC_TOOL) --buildPkg "midi.vescpkg:midi.lisp::0:README.md:midi"

midi:
	$(MAKE) -C $@

clean:
	rm -f midi.vescpkg
	$(MAKE) -C midi clean

.PHONY: all clean midi
