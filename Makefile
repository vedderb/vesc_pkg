PKGS = balance blacktip_dpv float refloat tnt vbms32 vbms32_micro
PKGS += lib_files lib_interpolation lib_nau7802 lib_pn532
PKGS += lib_ws2812 logui lib_code_server lib_midi lib_disp_ui
PKGS += vdisp lib_tca9535 vbms_harmony32

TEST_PKGS = blacktip_dpv

all: vesc_pkg_all.rcc

vesc_pkg_all.rcc: $(PKGS)
	rcc -binary res_all.qrc -o vesc_pkg_all.rcc

test: $(TEST_PKGS)

clean: $(PKGS)

$(PKGS):
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: all clean test $(PKGS)
