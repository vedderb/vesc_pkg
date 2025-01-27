VESC_TOOL ?= vesc_tool

all: balance.vescpkg

balance.vescpkg: balance
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:test' --testPkgDesc 'vesc:test'

balance:
	$(MAKE) -C $@

clean:
	rm -f balance.vescpkg
	$(MAKE) -C balance clean

.PHONY: all clean balance
