VESC_TOOL ?= vesc_tool

all: bq27441.vescpkg

bq27441.vescpkg:
	$(VESC_TOOL) --buildPkg "bq27441.vescpkg:bq27441.lisp::0:README.md:BQ27441 Driver"

clean:
	rm -f bq27441.vescpkg

.PHONY: all clean
