VESC_TOOL ?= vesc_tool

all: files.vescpkg

files.vescpkg:
	$(VESC_TOOL) --buildPkg "files.vescpkg:files.lisp::0:README.md:Files"

clean:
	rm -f files.vescpkg

.PHONY: all clean
