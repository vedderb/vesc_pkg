VESC_TOOL ?= vesc_tool

all: disp_ui.vescpkg

disp_ui.vescpkg:
	$(VESC_TOOL) --buildPkg "disp_ui.vescpkg:disp_ui.lisp::0:README.md:DispUI"

clean:
	rm -f disp_ui.vescpkg

.PHONY: all clean
