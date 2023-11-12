VESC_TOOL ?= C:\Users\X390\Drive\DEV_Design\VESC\build-vesc_tool-Desktop_Qt_5_15_2_MinGW_64_bit-Release\release\vesc_tool_6.05.exe

all: x1_unlocker.vescpkg

x1_unlocker.vescpkg:
	$(VESC_TOOL) --buildPkg "x1_unlocker.vescpkg:script.lisp::0:README.md:X1-Unlocker"

clean:
	rm -f x1_unlocker.vescpkg

.PHONY: all clean
