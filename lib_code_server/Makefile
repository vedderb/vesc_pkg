VESC_TOOL ?= vesc_tool

all: code_server.vescpkg

code_server.vescpkg:
	$(VESC_TOOL) --buildPkg "code_server.vescpkg:code_server.lisp::0:README.md:Code Server"

clean:
	rm -f code_server.vescpkg

.PHONY: all clean
