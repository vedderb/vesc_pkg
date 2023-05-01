/*
    Copyright 2019 - 2022 Sean Taylor
	Copyright 2022 Benjamin Vedder	benjamin@vedder.se

	This file is part of the VESC firmware.

	The VESC firmware is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    The VESC firmware is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "st_types.h"
#include "vesc_c_if.h"

#include <math.h>
#include <string.h>

HEADER

//define pins for trampa 100_250 board
/*NOTE: This will have to change if we are using a different board architecture

// Hall/encoder pins
#define HW_HALL_ENC_GPIO1		GPIOC
#define HW_HALL_ENC_PIN1		6
#define HW_HALL_ENC_GPIO2		GPIOC
#define HW_HALL_ENC_PIN2		7
#define HW_HALL_ENC_GPIO3		GPIOC
#define HW_HALL_ENC_PIN3		8
#define HW_ENC_TIM				TIM3
#define HW_ENC_TIM_AF			GPIO_AF_TIM3
#define HW_ENC_TIM_CLK_EN()		RCC_APB1PeriphClockCmd(RCC_APB1Periph_TIM3, ENABLE)
#define HW_ENC_EXTI_PORTSRC		EXTI_PortSourceGPIOC
#define HW_ENC_EXTI_PINSRC		EXTI_PinSource8
#define HW_ENC_EXTI_CH			EXTI9_5_IRQn
#define HW_ENC_EXTI_LINE		EXTI_Line8
#define HW_ENC_EXTI_ISR_VEC		EXTI9_5_IRQHandler
#define HW_ENC_TIM_ISR_CH		TIM3_IRQn
#define HW_ENC_TIM_ISR_VEC		TIM3_IRQHandler

// SPI pins -> IF we want to use this in the future
#define HW_SPI_DEV				SPID1
#define HW_SPI_GPIO_AF			GPIO_AF_SPI1
#define HW_SPI_PORT_NSS			GPIOA
#define HW_SPI_PIN_NSS			4
#define HW_SPI_PORT_SCK			GPIOA
#define HW_SPI_PIN_SCK			5
#define HW_SPI_PORT_MOSI		GPIOA
#define HW_SPI_PIN_MOSI			7
#define HW_SPI_PORT_MISO		GPIOA
#define HW_SPI_PIN_MISO			6

#define BMI160_SDA_GPIO			GPIOB
#define BMI160_SDA_PIN			4
#define BMI160_SCL_GPIO			GPIOB
#define BMI160_SCL_PIN			12
#define IMU_FLIP

*/
#define AksIM2_DATA_INVALID_THRESHOLD 20000
#define AksIM2_CONNECTION_ERROR_THRESHOLD 5

/*simple low pass filter*/
#define LP_FAST(value, sample, filter_constant) (value -= (filter_constant) * ((value) - (sample)))

//CRC calculation lookup table.
static const uint8_t ab_CRC8_LUT[256] = {
0x00, 0x97, 0xB9, 0x2E, 0xE5, 0x72, 0x5C, 0xCB, 0x5D, 0xCA, 0xE4, 0x73, 0xB8, 0x2F, 0x01, 0x96,
0xBA, 0x2D, 0x03, 0x94, 0x5F, 0xC8, 0xE6, 0x71, 0xE7, 0x70, 0x5E, 0xC9, 0x02, 0x95, 0xBB, 0x2C,
0xE3, 0x74, 0x5A, 0xCD, 0x06, 0x91, 0xBF, 0x28, 0xBE, 0x29, 0x07, 0x90, 0x5B, 0xCC, 0xE2, 0x75,
0x59, 0xCE, 0xE0, 0x77, 0xBC, 0x2B, 0x05, 0x92, 0x04, 0x93, 0xBD, 0x2A, 0xE1, 0x76, 0x58, 0xCF,
0x51, 0xC6, 0xE8, 0x7F, 0xB4, 0x23, 0x0D, 0x9A, 0x0C, 0x9B, 0xB5, 0x22, 0xE9, 0x7E, 0x50, 0xC7,
0xEB, 0x7C, 0x52, 0xC5, 0x0E, 0x99, 0xB7, 0x20, 0xB6, 0x21, 0x0F, 0x98, 0x53, 0xC4, 0xEA, 0x7D,
0xB2, 0x25, 0x0B, 0x9C, 0x57, 0xC0, 0xEE, 0x79, 0xEF, 0x78, 0x56, 0xC1, 0x0A, 0x9D, 0xB3, 0x24,
0x08, 0x9F, 0xB1, 0x26, 0xED, 0x7A, 0x54, 0xC3, 0x55, 0xC2, 0xEC, 0x7B, 0xB0, 0x27, 0x09, 0x9E,
0xA2, 0x35, 0x1B, 0x8C, 0x47, 0xD0, 0xFE, 0x69, 0xFF, 0x68, 0x46, 0xD1, 0x1A, 0x8D, 0xA3, 0x34,
0x18, 0x8F, 0xA1, 0x36, 0xFD, 0x6A, 0x44, 0xD3, 0x45, 0xD2, 0xFC, 0x6B, 0xA0, 0x37, 0x19, 0x8E,
0x41, 0xD6, 0xF8, 0x6F, 0xA4, 0x33, 0x1D, 0x8A, 0x1C, 0x8B, 0xA5, 0x32, 0xF9, 0x6E, 0x40, 0xD7,
0xFB, 0x6C, 0x42, 0xD5, 0x1E, 0x89, 0xA7, 0x30, 0xA6, 0x31, 0x1F, 0x88, 0x43, 0xD4, 0xFA, 0x6D,
0xF3, 0x64, 0x4A, 0xDD, 0x16, 0x81, 0xAF, 0x38, 0xAE, 0x39, 0x17, 0x80, 0x4B, 0xDC, 0xF2, 0x65,
0x49, 0xDE, 0xF0, 0x67, 0xAC, 0x3B, 0x15, 0x82, 0x14, 0x83, 0xAD, 0x3A, 0xF1, 0x66, 0x48, 0xDF,
0x10, 0x87, 0xA9, 0x3E, 0xF5, 0x62, 0x4C, 0xDB, 0x4D, 0xDA, 0xF4, 0x63, 0xA8, 0x3F, 0x11, 0x86,
0xAA, 0x3D, 0x13, 0x84, 0x4F, 0xD8, 0xF6, 0x61, 0xF7, 0x60, 0x4E, 0xD9, 0x12, 0x85, 0xAB, 0x3C
};

//Development note.
//Don't have prints that spam, will cause package to crash
typedef struct {
	stm32_gpio_t *nss;
	uint32_t nss_pin;
	stm32_gpio_t *sck;
	uint32_t sck_pin;
	stm32_gpio_t *mosi;
	uint32_t mosi_pin;
	stm32_gpio_t *miso;
	uint32_t miso_pin;
	//mutex_t mutex; // what is this inculde file?
} aksim2_gpio_t;

typedef struct {
	VESC_PIN nss;
	VESC_PIN sck;
	VESC_PIN mosi;
	VESC_PIN miso;
} vesc_pin_t;

typedef struct {
	uint32_t spi;
	float last_angle;
	uint32_t last_time;
	float last_timestep;
	uint32_t data_last_invalid_counter;
	uint8_t spi_coms_err_cnt;
	uint8_t spi_connected;
	uint32_t crc_err_cnt;
	float crc_err_rate;
	uint32_t enc_err_cnt;
	uint32_t enc_err_rate;
	uint8_t enc_data_error_raised;
	uint8_t enc_data_warning_raised;
} spi_t;

// Data type
// This is all persistent state of the application, which will be allocated in init. It
// is put here because variables can only be read-only when this program is loaded
// in flash without virtual memory in RAM (as all RAM already is dedicated to the
// main firmware and managed from there). This is probably the main limitation of
// loading applications in runtime, but it is not too bad to work around.
typedef struct {
	lib_thread thread;  	// AksIM-2 Thread
	aksim2_gpio_t gpio;		//gpio pins for AksIM-2 coms
	vesc_pin_t vesc_pins;
	spi_t spi;
	uint8_t crc_calc;
	uint8_t crc_recv;
	uint64_t crc_input;
} data;


static uint8_t CRC_SPI_97_64bit(uint64_t inputData) {
	uint8_t b_index = 0;
	uint8_t b_crc = 0;
	b_index = (uint8_t)((inputData >> 56u) & (uint64_t)0x000000FFu);
	b_crc = (uint8_t)((inputData >> 48u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)((inputData >> 40u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)((inputData >> 32u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)((inputData >> 24u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)((inputData >> 16u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)((inputData >> 8u) & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = (uint8_t)(inputData & (uint64_t)0x000000FFu);
	b_index = b_crc ^ ab_CRC8_LUT[b_index];
	b_crc = ab_CRC8_LUT[b_index];

	return b_crc; 
}

static bool check_crc(uint32_t msg, data * d) {

	uint8_t recv = msg & 0xFF;
	msg &= 0xFFFFFF00;
	msg >>= 8;

	uint8_t rx_buff[4] = {0};

	memcpy(rx_buff, &msg, sizeof(msg));
	uint64_t dw_CRCinputData = 0;
	uint8_t calculated_crc = 0;

//	dw_CRCinputData = ((uint64_t)rx_buff[0] << 32) + ((uint64_t)rx_buff[1] << 24) +
//						((uint64_t)rx_buff[2] << 16) + ((uint64_t)rx_buff[3] << 8) +
//						((uint64_t)rx_buff[4] << 0); 
//
//	dw_CRCinputData = ((uint64_t)rx_buff[0] << 32) + ((uint64_t)rx_buff[1] << 24) +
//						((uint64_t)rx_buff[2] << 16) + ((uint64_t)rx_buff[3] << 8);
//
//	//This also works... don't know if it's better
	dw_CRCinputData = (uint64_t)msg;
	calculated_crc = ~(CRC_SPI_97_64bit(dw_CRCinputData)) & 0xFF;		//inverted CRC

	//copy crc data for debug, remove later
	if (d) {
		d->crc_calc = calculated_crc;
		d->crc_input = dw_CRCinputData;
		d->crc_recv = recv;
	}

	//check this with recv CRC
	return (calculated_crc == (recv & 0xFF));	//just compare to first 8 bits
}


static void initialise_data(data *d) {
	d->thread = NULL;
	//init gpio pins for AksIM-2 coms
	//currently using sense port (hall). Set VESC pin type agnostic to firmware updates
//	d->vesc_pins.nss = VESC_PIN_HALL3;
//	d->vesc_pins.sck = VESC_PIN_HALL1;
//	d->vesc_pins.miso = VESC_PIN_HALL2;		//check this
//	d->vesc_pins.mosi = VESC_PIN_ADC1;		//not used

	d->vesc_pins.nss = VESC_PIN_COMM_RX;
	d->vesc_pins.sck = VESC_PIN_ADC1;
	d->vesc_pins.miso = VESC_PIN_ADC2;		//check this
	d->vesc_pins.mosi = VESC_PIN_COMM_TX;		//not used

	//get the gpio for these pins. Need it to set and clear pad
	VESC_IF->io_get_st_pin(d->vesc_pins.nss, (void**)&d->gpio.nss, &d->gpio.nss_pin);
	VESC_IF->io_get_st_pin(d->vesc_pins.sck, (void**)&d->gpio.sck, &d->gpio.sck_pin);
	VESC_IF->io_get_st_pin(d->vesc_pins.miso, (void**)&d->gpio.miso, &d->gpio.miso_pin);

	if(d->gpio.nss == NULL || d->gpio.sck == NULL || d->gpio.miso == NULL ||
			d->gpio.nss_pin == 0 || d->gpio.sck_pin == 0 || d->gpio.miso_pin == 0)
	{
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("AksIM2 App: io_get_st_pin failed for one or more pins");
			VESC_IF->printf("AksIM2 App: pins %d, %d, %d", d->gpio.nss_pin, d->gpio.sck_pin, d->gpio.miso_pin);
		}
	}

	//not using mosi
	d->gpio.mosi = NULL;
	d->gpio.mosi_pin = 0;

	//set spi_t data to 0
	d->spi.spi = d->spi.last_angle = d->spi.last_time = d->spi.last_timestep = d->spi.data_last_invalid_counter =
		d->spi.spi_coms_err_cnt = d->spi.spi_connected = d->spi.crc_err_cnt = d->spi.crc_err_rate =
		d->spi.enc_data_error_raised = d->spi.enc_data_warning_raised = 0;
}

static void spi_bb_init(data * d) {
	//MUTEX?

	//see spi_bb.cc for reference on PAL_MODEs 
	VESC_IF->set_pad_mode(d->gpio.miso, d->gpio.miso_pin, (PAL_STM32_MODE_INPUT | PAL_STM32_PUDR_PULLUP));
	VESC_IF->set_pad_mode(d->gpio.sck, d->gpio.sck_pin, ((PAL_STM32_MODE_OUTPUT | PAL_STM32_OTYPE_PUSHPULL) | PAL_STM32_OSPEED_HIGHEST));
	VESC_IF->set_pad_mode(d->gpio.nss, d->gpio.nss_pin, ((PAL_STM32_MODE_OUTPUT | PAL_STM32_OTYPE_PUSHPULL) | PAL_STM32_OSPEED_HIGHEST));

	//io_set_mode does not have speed options, if there are issues with sampling rate, try using set_pad_mode...
	//if(!VESC_IF->io_set_mode(d->vesc_pins.miso, VESC_PIN_MODE_INPUT_PULL_UP)) {
	//	if (!VESC_IF->app_is_output_disabled()) {
	//		VESC_IF->printf("AksIM2 App: io_set_mode failed for miso pin");
	//	}
	//}
	//if(!VESC_IF->io_set_mode(d->vesc_pins.sck, VESC_PIN_MODE_OUTPUT)) {
	//	if (!VESC_IF->app_is_output_disabled()) {
	//		VESC_IF->printf("AksIM2 App: io_set_mode failed for sck pin");
	//	}
	//}
	//if(!VESC_IF->io_set_mode(d->vesc_pins.nss, VESC_PIN_MODE_OUTPUT)) {
	//	if (!VESC_IF->app_is_output_disabled()) {
	//		VESC_IF->printf("AksIM2 App: io_set_mode failed for nss pin");
	//	}
	//}

	/*if (d->gpio.mosi) {
		VESC_IF->set_pad_mode(d->gpio.mosi, d->gpio.mosi_pin, 6U | PAL_STM32_OSPEED_HIGHEST);
		VESC_IF->set_pad(d->gpio.mosi, d->gpio.mosi_pin);
		VESC_IF->set_pad(d->gpio.nss, d->gpio.nss_pin);
	}*/
}

static void spi_bb_deint(data *d) {
	//VESC_IF->set_pad_mode(d->gpio.miso, d->gpio.miso_pin, 3U);
	//VESC_IF->set_pad_mode(d->gpio.sck, d->gpio.sck_pin, 3U);
	//VESC_IF->set_pad_mode(d->gpio.nss, d->gpio.nss_pin, 3U);
	if(!VESC_IF->io_set_mode(d->vesc_pins.miso, VESC_PIN_MODE_INPUT_PULL_UP)) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("AksIM2 App: io_set_mode failed for miso pin");
		}
	}
	if(!VESC_IF->io_set_mode(d->vesc_pins.sck, VESC_PIN_MODE_INPUT_PULL_UP)) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("AksIM2 App: io_set_mode failed for sck pin");
		}
	}
	if(!VESC_IF->io_set_mode(d->vesc_pins.nss, VESC_PIN_MODE_INPUT_PULL_UP)) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("AksIM2 App: io_set_mode failed for nss pin");
		}
	}

	/*if (d->gpio.mosi) {
		VESC_IF->set_pad_mode(d->gpio.mosi, d->gpio.mosi_pin, 3U);
	}*/
}

//__NOP approx 250 ns
static void spi_bb_delay(int n) {
	for (volatile int i = 0; i < n; i++) {
		__NOP();
	}
}

static void spi_bb_begin(data *d) {
	//set nss low
	spi_bb_delay(40);
	VESC_IF->clear_pad(d->gpio.nss, d->gpio.nss_pin);
	spi_bb_delay(40);		//enforce > 5us delay before reading
}

static void spi_bb_end(data *d) {
	//set nss high
	spi_bb_delay(40);
	VESC_IF->set_pad(d->gpio.nss, d->gpio.nss_pin);
	spi_bb_delay(40);
}

void spi_bb_transfer_32(
		data *d, 
		uint32_t *in_buf, 
		const uint32_t *out_buf, 
		int length
		) {

	for (int i = 0; i < length; i++) {
		uint32_t send = out_buf ? out_buf[i] : 0xFFFFFF;
		uint32_t receive = 0;

		for (int bit = 0; bit < 32; bit++) {
			if(d->gpio.mosi) {
				VESC_IF->io_write(d->vesc_pins.mosi, send >> 31);
				send <<= 1;
			}

			VESC_IF->set_pad(d->gpio.sck, d->gpio.sck_pin);
			spi_bb_delay(4);

			int samples = 0;
			samples += VESC_IF->io_read(d->vesc_pins.miso);
			__NOP();
			samples += VESC_IF->io_read(d->vesc_pins.miso);
			__NOP();
			samples += VESC_IF->io_read(d->vesc_pins.miso);
			__NOP();
			samples += VESC_IF->io_read(d->vesc_pins.miso);
			__NOP();
			samples += VESC_IF->io_read(d->vesc_pins.miso);

			receive <<= 1;
			if (samples > 2) {
				receive |= 1;
			}

			VESC_IF->clear_pad(d->gpio.sck, d->gpio.sck_pin);
			spi_bb_delay(4);
		}

		if (in_buf) {
			in_buf[i] = receive;
		}
	}
}

static void determine_if_connected(spi_t *spi, bool was_valid) {
	if (spi == NULL) {
		return;
	}

	if (was_valid) {
		if (spi->spi_coms_err_cnt) {
			spi->spi_coms_err_cnt--;
		} else {
			spi->spi_connected = 1;
		}
	} else {
		spi->spi_coms_err_cnt++;
		if (spi->spi_coms_err_cnt >= AksIM2_CONNECTION_ERROR_THRESHOLD) {
			spi->spi_connected = 0;
			spi->spi_coms_err_cnt = AksIM2_CONNECTION_ERROR_THRESHOLD;
		}
	}
}

static float AksIM2_read (void) {
	data* d = (data*)ARG;
	return (float)d->spi.last_angle;
}

static bool AksIM2_fault (void) {
	data* d = (data*)ARG;
	return (bool)!d->spi.spi_connected;
}

static char * AksIM2_print (void) {
	char * txt = "printing in aksim2";
	return txt;
}

// Register get_debug as a lisp extension
static lbm_value ext_aksim_dbg(lbm_value *args, lbm_uint argn) {

	data* d = (data*)ARG;

	if (argn != 1 || !VESC_IF->lbm_is_number(args[0]) || d == NULL) {
		return VESC_IF->lbm_enc_sym_eerror;
	}

	int idx = VESC_IF->lbm_dec_as_i32(args[0]);

	switch(idx) {
		case 1:
			return VESC_IF->lbm_enc_u32(d->spi.spi);
		case 2:
			return VESC_IF->lbm_enc_float(d->spi.last_angle);
		case 3:
			return VESC_IF->lbm_enc_u32(d->spi.last_time);
		case 4:
			return VESC_IF->lbm_enc_i(d->spi.crc_err_cnt);
		case 5:
			return VESC_IF->lbm_enc_float(d->spi.crc_err_rate);
		case 6:
			return VESC_IF->lbm_enc_i(d->spi.spi_connected);
		case 7:
			return VESC_IF->lbm_enc_u32(d->spi.data_last_invalid_counter);
		case 8:
			if (!VESC_IF->app_is_output_disabled()) {
				VESC_IF->printf("calc: %d, recv: %d ", d->crc_calc, d->crc_recv );
			}
			return VESC_IF->lbm_enc_u(0);
		case 9:
			return VESC_IF->lbm_enc_float(d->spi.last_timestep);
		case 10:
			return VESC_IF->lbm_enc_i(d->spi.enc_err_cnt);
		default:
			return VESC_IF->lbm_enc_sym_eerror;
	}
}

static void askim_thd(void * arg) {
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("AksIM2 App: thread started!");
	}
	data *d = (data*)arg;


	if (d == NULL) {
		VESC_IF->printf("AksIM2 App: thread started with NULL argument!");
		return;
	}

	spi_bb_init(d);

	while(!VESC_IF->should_terminate()) {
		uint32_t pos;
		float timestep = VESC_IF->timer_seconds_elapsed_since(d->spi.last_time);
		d->spi.last_timestep = timestep;
		if (timestep > 1.0) { timestep = 1.0; }

		d->spi.last_time = VESC_IF->timer_time_now();
		//NOT CURRENTLY USING MOSI BUT WOULD HANDLE COMANDS HERE
		//if (d->gpio.mosi) {
		// see spi_bb.c
		//}

		//read spi data
		spi_bb_begin(d);
		spi_bb_transfer_32(d, &pos, 0, 1);
		spi_bb_end(d);
		d->spi.spi = pos;

		//check connection to encoder. If we have read all high or all low something aint right
		if(0x0000 == pos || 0xFFFFFFFF == pos) {
			d->spi.data_last_invalid_counter++;
		} else {
			d->spi.data_last_invalid_counter = 0;
			determine_if_connected(&d->spi, true);
		}

		if (d->spi.data_last_invalid_counter >= AksIM2_DATA_INVALID_THRESHOLD) {
			determine_if_connected(&d->spi, false);
			d->spi.data_last_invalid_counter = AksIM2_DATA_INVALID_THRESHOLD;
		}

		//this check sum is failing lots..
		if (check_crc(pos, d)) {
			//check error and warning flags
			(pos & (1 << 7)) ?
				(d->spi.enc_data_error_raised = false) : (d->spi.enc_data_error_raised = true);
			(pos & (1 << 8)) ? 
				(d->spi.enc_data_warning_raised = false) : (d->spi.enc_data_warning_raised = true);

			//also getting lots of error bits
			if (!d->spi.enc_data_error_raised) {
				//get the angle
				pos &= 0xFFFFC000;											//mask out the unused 4 bits, error/warning flags and CRC
				pos >>= 14;													//shift it so data is in the lower 18 bits
				d->spi.last_angle = ((float) pos * 360.0) / 262144.0;		//calculate angle

				LP_FAST(d->spi.enc_err_rate, 0.0, timestep);
			}
			else {
				d->spi.enc_err_cnt++;
				LP_FAST(d->spi.enc_err_rate, 1.0, timestep);
			}
			LP_FAST(d->spi.crc_err_rate, 0.0, timestep);
		}
		else {
			d->spi.crc_err_cnt++;
			LP_FAST(d->spi.crc_err_rate, 1.0, timestep);
		}

		//thread needs some delay (more then just in msg timing) to release the cpu
		//TODO find good delay
		VESC_IF->sleep_us(10);
	}
	spi_bb_deint(d);
}

// Called when code is stopped
static void stop(void *arg) {
	data *d = (data*)arg;
	
	spi_bb_deint(d);	//incase it didn't get called in the thread

	VESC_IF->encoder_set_custom_callbacks(NULL, NULL, NULL);
	VESC_IF->set_app_data_handler(NULL);
	VESC_IF->request_terminate(d->thread);
	//VESC_IF->conf_custom_clear_configs();
	VESC_IF->free(d);

	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("AksIM-2 App Terminated");
	}
}

INIT_FUN(lib_info *info) {
	INIT_START
	if (!VESC_IF->app_is_output_disabled()) {
		VESC_IF->printf("Init AksIM2");
	}

	data *d = VESC_IF->malloc(sizeof(data));
	memset(d, 0, sizeof(data));
	if (!d) {
		if (!VESC_IF->app_is_output_disabled()) {
			VESC_IF->printf("AksIM2 App: Out of memory, startup failed!");
		}
		return false;
	}

	initialise_data(d);

	info->stop_fun = stop;
	info->arg = d;

	d->thread = VESC_IF->spawn(askim_thd, 2048, "AksIM2 main", d);
	VESC_IF->encoder_set_custom_callbacks(AksIM2_read, AksIM2_fault, AksIM2_print);
	VESC_IF->lbm_add_extension("ext-aksim2-dbg", ext_aksim_dbg);

	return true;
}
