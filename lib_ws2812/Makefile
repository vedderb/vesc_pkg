VESC_TOOL ?= vesc_tool

all: ws2812.vescpkg

ws2812.vescpkg: ws2812
	$(VESC_TOOL) --buildPkg "ws2812.vescpkg:ws2812.lisp::0:README.md:WS2812 Driver"

ws2812:
	$(MAKE) -C $@

clean:
	rm -rf ws2812.vescpkg
	$(MAKE) -C ws2812 clean

.PHONY: all clean ws2812
