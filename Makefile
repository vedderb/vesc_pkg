PKGS = balance float tnt lib_files lib_interpolation lib_nau7802 lib_pn532 lib_ws2812 logui lib_code_server

all: vesc_pkg_all.rcc

vesc_pkg_all.rcc: $(PKGS)
	rcc -binary res_all.qrc -o vesc_pkg_all.rcc

clean: $(PKGS)

$(PKGS):
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: all clean $(PKGS)
