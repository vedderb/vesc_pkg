VESC_TOOL ?= vesc_tool

all: pubmote.vescpkg

pubmote.vescpkg: pubmote.lisp README.md
	$(VESC_TOOL) --buildPkg "pubmote.vescpkg:pubmote.lisp::0:README.md:Pubmote"

clean:
	rm -f pubmote.vescpkg

.PHONY: all clean
