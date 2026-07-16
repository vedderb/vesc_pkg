/*
	Copyright 2026 Benjamin Vedder	benjamin@vedder.se

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

/*
 * Native library C interface for the VESC Express.
 *
 * This is a NEW interface, separate from the bldc (STM32 motor controller)
 * vesc_c_if. It starts from the platform-neutral core - LispBM access,
 * threads, timing, mutexes/semaphores, memory and printf - and contains no
 * motor, CAN or peripheral functions. More slots will be appended over time.
 *
 * Compatibility rules:
 *  - New function pointers are ONLY ever added at the END of the struct, so
 *    libs built against older headers keep working on newer firmware. Added
 *    slots are null-pointers on firmware that predates them - a lib that
 *    wants to run on older firmware can check them for NULL.
 *  - VESC_C_IF_VERSION is bumped ONLY on a breaking layout change. INIT_START
 *    compares it against the firmware's table (first slot, read before any
 *    function in the table is called) and fails the lib init on mismatch.
 */

#ifndef VESC_C_IF_H
#define VESC_C_IF_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Layout version of the vesc_c_if struct below. Only bumped on breaking
// changes; appended slots do NOT bump it.
#define VESC_C_IF_VERSION 1

#define NATIVE_LIB_MAGIC 0xCAFEBABE

// Container magic for relocatable libs that the firmware copies into RAM
// and patches at load time. Used on targets that cannot run position-
// independent code in place (ESP32-S3 / Xtensa). Layout: magic,
// version, code_size, data_size, entry_offset, reloc_count, relocs[],
// code[], data[].
#define NATIVE_LIB_RELOC_MAGIC 0xCAFEBABF

// System tick, as returned by system_time_ticks
typedef uint32_t systime_t;

#ifdef IS_VESC_LIB
// LBM types, provided by lispbm.h when compiling the firmware itself.
typedef uint32_t lbm_value;
typedef uint32_t lbm_type;
typedef uint32_t lbm_cid;

typedef uint32_t lbm_uint;
typedef int32_t  lbm_int;
typedef float    lbm_float;

typedef struct {
	uint8_t *buf;
	lbm_uint buf_size;
	lbm_uint buf_pos;
} lbm_flat_value_t;

typedef struct {
	lbm_uint size;            /// Number of elements
	lbm_uint *data;           /// pointer to lbm_memory array or C array.
} lbm_array_header_t;

typedef lbm_value (*extension_fptr)(lbm_value*,lbm_uint);

// For double precision literals
#define D(x) 				((double)x##L)

// CAN status messages and hardware type. The firmware uses the definitions
// from datatypes.h; libs get them here (layouts must match).
typedef struct { int id; systime_t rx_time; float rpm; float current; float duty; } can_status_msg;
typedef struct { int id; systime_t rx_time; float amp_hours; float amp_hours_charged; } can_status_msg_2;
typedef struct { int id; systime_t rx_time; float watt_hours; float watt_hours_charged; } can_status_msg_3;
typedef struct { int id; systime_t rx_time; float temp_fet; float temp_motor; float current_in; float pid_pos_now; } can_status_msg_4;
typedef struct { int id; systime_t rx_time; float v_in; int32_t tacho_value; } can_status_msg_5;
typedef struct { int id; systime_t rx_time; float adc_1; float adc_2; float adc_3; float ppm; } can_status_msg_6;
typedef enum { HW_TYPE_VESC = 0, HW_TYPE_VESC_BMS, HW_TYPE_CUSTOM_MODULE } HW_TYPE;

// AHRS attitude state (mirrors drivers/imu/ahrs.h; firmware uses that).
typedef struct {
	float q0; float q1; float q2; float q3;
	float integralFBx; float integralFBy; float integralFBz;
	float accMagP;
	int initialUpdateDone;
	float acc_confidence_decay;
	float kp;
	float ki;
	float beta;
} ATTITUDE_INFO;

// Persistent EEPROM/NVS variable (mirrors flash_helper.h).
typedef union {
	uint32_t as_u32;
	int32_t as_i32;
	float as_float;
} eeprom_var;

// BMS values (mirrors datatypes.h). Returned by bms_get_values; reflects the
// pack the firmware is tracking (over CAN or an on-board BMS).
#define BMS_MAX_CELLS	50
#define BMS_MAX_TEMPS	50
#define BMS_STATUS_LEN	41
typedef struct {
	float v_tot;
	float v_charge;
	float i_in;
	float i_in_ic;
	float ah_cnt;
	float wh_cnt;
	int cell_num;
	float v_cell[BMS_MAX_CELLS];
	bool bal_state[BMS_MAX_CELLS];
	int temp_adc_num;
	float temps_adc[BMS_MAX_TEMPS];
	float temp_ic;
	float temp_hum;
	float hum;
	float pressure;
	float temp_max_cell;
	float v_cell_min;
	float v_cell_max;
	float soc;
	float soh;
	int can_id;
	float ah_cnt_chg_total;
	float wh_cnt_chg_total;
	float ah_cnt_dis_total;
	float wh_cnt_dis_total;
	int is_charging;
	int is_balancing;
	int is_charge_allowed;
	int data_version;
	char status[BMS_STATUS_LEN];
	uint32_t update_time;
} bms_values;

// GNSS / NMEA state (mirrors nmea.h). Returned by gnss_get_state.
typedef struct {
	double lat;
	double lon;
	double height;
	int ms_today;
	int n_sat;
	int fix_type;
	float h_dop;
	float diff_age;
	uint32_t update_time;
} nmea_gga_info_t;
typedef struct {
	int prn;
	float elevation;
	float azimuth;
	float snr;
	bool lock;
	float base_snr;
	bool base_lock;
	bool local_lock;
} nmea_gsv_sat_t;
typedef struct {
	int sat_num;
	int sentences;
	int sat_last;
	int sat_num_base;
	nmea_gsv_sat_t sats[32];
	uint32_t update_time;
} nmea_gsv_info_t;
typedef struct {
	int hh; int mm; int ss; int ms;
	int yy; int mo; int dd;
	float speed; // Ground speed, meters per second
	uint32_t update_time;
} nmea_rmc_info_t;
typedef struct {
	int gga_cnt;
	int gsv_gp_cnt;
	int gsv_gl_cnt;
	int rmc_cnt;
	nmea_gga_info_t gga;
	nmea_gsv_info_t gsv;
	nmea_rmc_info_t rmc;
} nmea_state_t;
#endif

typedef bool (*load_extension_fptr)(char*,extension_fptr);

typedef void* lib_thread;
typedef void* lib_mutex;
typedef void* lib_semaphore;

// MQTT client configuration (compact subset of esp-mqtt's config). Set uri
// ("mqtt://host:1883" or "mqtts://host:8883") OR host+port. All strings are
// copied by the client, so they need not outlive the mqtt_init call. Leave
// unused pointers NULL and unused ints 0.
typedef struct {
	const char *uri;             // takes precedence over host/port when set
	const char *host;            // used when uri is NULL
	int port;
	const char *client_id;       // NULL = auto-generated
	const char *username;        // NULL = no authentication
	const char *password;
	int keepalive;               // seconds, 0 = default (120)
	const char *lwt_topic;       // last will and testament, NULL = none
	const char *lwt_msg;
	int lwt_qos;
	int lwt_retain;
	const char *server_cert_pem; // CA cert (PEM) for mqtts://, NULL = none
} mqtt_config;

// MQTT event delivered to the callback registered with mqtt_set_event_handler.
// Pointers are valid only for the duration of the callback. Large payloads may
// arrive as several DATA events; use data_offset/total_data_len to reassemble.
typedef struct {
	int event_id;        // 0=CONNECTED 1=DISCONNECTED 2=DATA 3=SUBSCRIBED
	                     // 4=UNSUBSCRIBED 5=PUBLISHED 6=ERROR (-1=other)
	const char *topic;
	int topic_len;
	const char *data;
	int data_len;
	int data_offset;     // offset of this chunk within the full payload
	int total_data_len;  // full payload length
	int msg_id;
	int qos;
	bool retain;
} mqtt_event;

// BLE GATT attribute permission bits (ble_chr_def/ble_desc_def .perm).
#define VESC_BLE_PERM_READ      0x01
#define VESC_BLE_PERM_WRITE     0x10
// BLE characteristic property bits (ble_chr_def .prop).
#define VESC_BLE_PROP_BROADCAST 0x01
#define VESC_BLE_PROP_READ      0x02
#define VESC_BLE_PROP_WRITE_NR  0x04
#define VESC_BLE_PROP_WRITE     0x08
#define VESC_BLE_PROP_NOTIFY    0x10
#define VESC_BLE_PROP_INDICATE  0x20

// A BLE UUID. len is 2 (16-bit), 4 (32-bit) or 16 (128-bit); uuid holds the
// bytes little-endian, as BLE expects.
typedef struct {
	uint8_t len;
	uint8_t uuid[16];
} ble_uuid;

// A GATT descriptor definition (used inside ble_chr_def).
typedef struct {
	ble_uuid uuid;
	uint16_t perm;        // VESC_BLE_PERM_* bitmask
	uint16_t max_len;     // maximum value length
	uint16_t init_len;    // initial value length (0 for none)
	const uint8_t *init;  // initial value, copied internally (may be NULL)
} ble_desc_def;

// A GATT characteristic definition (passed to ble_add_service).
typedef struct {
	ble_uuid uuid;
	uint16_t perm;        // VESC_BLE_PERM_* bitmask
	uint16_t prop;        // VESC_BLE_PROP_* bitmask
	uint16_t max_len;
	uint16_t init_len;
	const uint8_t *init;
	uint16_t descr_count;
	const ble_desc_def *descrs; // may be NULL
} ble_chr_def;

/*
 * Function pointer struct. Always add new function pointers to the end in
 * order to not break compatibility with old binaries. If a function is not
 * available (e.g. in an old firmware) it will be a null-pointer.
 */
typedef struct {
	// Interface layout version, always the first slot. Read by INIT_START
	// before anything else in the table is used.
	uint32_t if_version;

	// LBM: extensions, symbols and errors
	load_extension_fptr lbm_add_extension;
	int (*lbm_set_error_reason)(char *str);
	int (*lbm_add_symbol_const)(const char *, lbm_uint *);
	int (*lbm_get_symbol_by_name)(const char *name, lbm_uint* id);

	// LBM: evaluator control and messaging
	void (*lbm_block_ctx_from_extension)(void);
	bool (*lbm_unblock_ctx)(lbm_cid, lbm_flat_value_t*);
	bool (*lbm_unblock_ctx_unboxed)(lbm_cid cid, lbm_value unboxed);
	lbm_cid (*lbm_get_current_cid)(void);
	int (*lbm_send_message)(lbm_cid cid, lbm_value msg);
	void (*lbm_pause_eval_with_gc)(uint32_t num_free);
	void (*lbm_continue_eval)(void);
	bool (*lbm_eval_is_paused)(void);

	// LBM: heap and values
	lbm_value (*lbm_cons)(lbm_value car, lbm_value cdr);
	lbm_value (*lbm_car)(lbm_value val);
	lbm_value (*lbm_cdr)(lbm_value val);
	lbm_value (*lbm_list_destructive_reverse)(lbm_value list);
	bool (*lbm_create_byte_array)(lbm_value *value, lbm_uint num_elt);

	// LBM: encoding
	lbm_value (*lbm_enc_i)(lbm_int x);
	lbm_value (*lbm_enc_u)(lbm_uint x);
	lbm_value (*lbm_enc_char)(uint8_t x);
	lbm_value (*lbm_enc_float)(float f);
	lbm_value (*lbm_enc_u32)(uint32_t u);
	lbm_value (*lbm_enc_i32)(int32_t i);
	lbm_value (*lbm_enc_sym)(lbm_uint s);

	// LBM: decoding
	float (*lbm_dec_as_float)(lbm_value val);
	uint32_t (*lbm_dec_as_u32)(lbm_value val);
	int32_t (*lbm_dec_as_i32)(lbm_value val);
	uint8_t (*lbm_dec_char)(lbm_value x);
	char* (*lbm_dec_str)(lbm_value);
	lbm_uint (*lbm_dec_sym)(lbm_value x);

	// LBM: type checks
	bool (*lbm_is_byte_array)(lbm_value val);
	bool (*lbm_is_cons)(lbm_value x);
	bool (*lbm_is_number)(lbm_value x);
	bool (*lbm_is_char)(lbm_value x);
	bool (*lbm_is_symbol)(lbm_value x);
	bool (*lbm_is_symbol_nil)(lbm_uint);
	bool (*lbm_is_symbol_true)(lbm_uint);

	// LBM: symbol constants
	lbm_uint lbm_enc_sym_nil;
	lbm_uint lbm_enc_sym_true;
	lbm_uint lbm_enc_sym_terror;
	lbm_uint lbm_enc_sym_eerror;
	lbm_uint lbm_enc_sym_merror;

	// LBM: flat values
	bool (*lbm_start_flatten)(lbm_flat_value_t *v, size_t buffer_size);
	bool (*lbm_finish_flatten)(lbm_flat_value_t *v);
	bool (*f_cons)(lbm_flat_value_t *v);
	bool (*f_sym)(lbm_flat_value_t *v, lbm_uint sym);
	bool (*f_i)(lbm_flat_value_t *v, lbm_int i);
	bool (*f_b)(lbm_flat_value_t *v, uint8_t b);
	bool (*f_i32)(lbm_flat_value_t *v, int32_t w);
	bool (*f_u32)(lbm_flat_value_t *v, uint32_t w);
	bool (*f_float)(lbm_flat_value_t *v, float f);
	bool (*f_i64)(lbm_flat_value_t *v, int64_t w);
	bool (*f_u64)(lbm_flat_value_t *v, uint64_t w);
	bool (*f_lbm_array)(lbm_flat_value_t *v, uint32_t num_elts, uint8_t *data);

	// Os: time and sleep
	void (*sleep_ms)(uint32_t ms);
	void (*sleep_us)(uint32_t us);
	float (*system_time)(void); // Time since boot in seconds
	float (*ts_to_age_s)(systime_t ts); // Age of timestamp in seconds
	// Time since boot in system ticks (see SYSTEM_TICK_RATE_HZ). Use
	// ts_to_age_s to get the age of a timestamp in seconds; it handles
	// overflows.
	systime_t (*system_time_ticks)(void);
	void (*sleep_ticks)(systime_t ticks);
	// High resolution timer for short busy-wait sleeps and time
	// measurement, in microseconds.
	uint32_t (*timer_time_now)(void);
	float (*timer_seconds_elapsed_since)(uint32_t time);
	void (*timer_sleep)(float seconds);

	// Os: memory and IO
	int (*printf)(const char *str, ...);
	void* (*malloc)(size_t bytes);
	void (*free)(void *ptr);

	// Os: threads
	lib_thread (*spawn)(void (*fun)(void *arg), size_t stack_size, const char *name, void *arg);
	void (*request_terminate)(lib_thread thd);
	bool (*should_terminate)(void);
	// Set priority of current thread.
	// Range: -5 to 5, -5 is lowest, 0 is normal, 5 is highest
	void (*thread_set_priority)(int priority);
	void** (*get_arg)(uint32_t prog_addr);

	// Os: mutex
	lib_mutex (*mutex_create)(void); // Use VESC_IF->free on the mutex when done with it
	void (*mutex_lock)(lib_mutex);
	void (*mutex_unlock)(lib_mutex);

	// Os: semaphore
	lib_semaphore (*sem_create)(void); // Use VESC_IF->free on the semaphore when done with it
	void (*sem_wait)(lib_semaphore);
	void (*sem_signal)(lib_semaphore);
	bool (*sem_wait_to)(lib_semaphore, systime_t); // Returns false on timeout
	void (*sem_reset)(lib_semaphore);

	// OS: device / firmware identification
	int         (*fw_version_major)(void);
	int         (*fw_version_minor)(void);
	int         (*fw_version_test)(void);
	const char* (*hw_name)(void);
	const char* (*chip_name)(void);
	void        (*get_mac)(uint8_t *buf);

	// CAN bus. Transmit raw standard/extended frames, or register a callback
	// to receive them (return true from the callback to consume the frame).
	// The can_set_* / can_get_status_* helpers command and read other VESC-
	// protocol devices on the bus.
	void (*can_transmit_sid)(uint32_t id, const uint8_t *data, uint8_t len);
	void (*can_transmit_eid)(uint32_t id, const uint8_t *data, uint8_t len);
	void (*can_send_buffer)(uint8_t controller_id, uint8_t *data, unsigned int len, uint8_t send);
	void (*can_set_sid_rx_callback)(bool (*p_func)(uint32_t id, uint8_t *data, uint8_t len));
	void (*can_set_eid_rx_callback)(bool (*p_func)(uint32_t id, uint8_t *data, uint8_t len));
	void (*can_set_duty)(uint8_t controller_id, float duty);
	void (*can_set_current)(uint8_t controller_id, float current);
	void (*can_set_current_off_delay)(uint8_t controller_id, float current, float off_delay);
	void (*can_set_current_brake)(uint8_t controller_id, float current);
	void (*can_set_rpm)(uint8_t controller_id, float rpm);
	void (*can_set_pos)(uint8_t controller_id, float pos);
	void (*can_set_current_rel)(uint8_t controller_id, float current_rel);
	void (*can_set_current_rel_off_delay)(uint8_t controller_id, float current_rel, float off_delay);
	void (*can_set_current_brake_rel)(uint8_t controller_id, float current_rel);
	bool (*can_ping)(uint8_t controller_id, HW_TYPE *hw_type);
	can_status_msg*   (*can_get_status_msg_index)(int index);
	can_status_msg*   (*can_get_status_msg_id)(int id);
	can_status_msg_2* (*can_get_status_msg_2_index)(int index);
	can_status_msg_2* (*can_get_status_msg_2_id)(int id);
	can_status_msg_3* (*can_get_status_msg_3_index)(int index);
	can_status_msg_3* (*can_get_status_msg_3_id)(int id);
	can_status_msg_4* (*can_get_status_msg_4_index)(int index);
	can_status_msg_4* (*can_get_status_msg_4_id)(int id);
	can_status_msg_5* (*can_get_status_msg_5_index)(int index);
	can_status_msg_5* (*can_get_status_msg_5_id)(int id);
	can_status_msg_6* (*can_get_status_msg_6_index)(int index);
	can_status_msg_6* (*can_get_status_msg_6_id)(int id);

	// App comms: send a custom-app-data packet to the connected VESC Tool /
	// app (over whatever link is active - USB, BLE, ...), or register a
	// handler to receive custom-app-data packets.
	void (*send_app_data)(unsigned char *data, unsigned int len);
	bool (*set_app_data_handler)(void(*func)(unsigned char *data, unsigned int len));

	// IMU: orientation, raw sensors, and a per-sample read callback. Present
	// only on boards with an IMU; check imu_startup_done().
	bool (*imu_startup_done)(void);
	float (*imu_get_roll)(void);
	float (*imu_get_pitch)(void);
	float (*imu_get_yaw)(void);
	void (*imu_get_rpy)(float *rpy);
	void (*imu_get_accel)(float *accel);
	void (*imu_get_gyro)(float *gyro);
	void (*imu_get_mag)(float *mag);
	void (*imu_derotate)(float *input, float *output);
	void (*imu_get_accel_derotated)(float *accel);
	void (*imu_get_gyro_derotated)(float *gyro);
	void (*imu_get_quaternions)(float *q);
	void (*imu_get_calibration)(float yaw, float *imu_cal);
	void (*imu_set_read_callback)(void (*func)(float *acc, float *gyro, float *mag, float dt));

	// AHRS: run your own sensor fusion over an ATTITUDE_INFO you own.
	void (*ahrs_init_attitude_info)(ATTITUDE_INFO *att);
	void (*ahrs_update_all_parameters)(ATTITUDE_INFO *att, float confidence_decay, float kp, float ki, float beta);
	void (*ahrs_update_initial_orientation)(float *accelXYZ, float *magXYZ, ATTITUDE_INFO *att);
	void (*ahrs_update_mahony_imu)(float *gyroXYZ, float *accelXYZ, float dt, ATTITUDE_INFO *att);
	void (*ahrs_update_madgwick_imu)(float *gyroXYZ, float *accelXYZ, float dt, ATTITUDE_INFO *att);
	float (*ahrs_get_roll)(ATTITUDE_INFO *att);
	float (*ahrs_get_pitch)(ATTITUDE_INFO *att);
	float (*ahrs_get_yaw)(ATTITUDE_INFO *att);
	void (*ahrs_get_roll_pitch_yaw)(float *rpy, ATTITUDE_INFO *att);

	// Persistent storage: read/write a variable by address 0..255 (NVS-backed,
	// shared with the lisp eeprom-store/-read extensions).
	bool (*store_eeprom_var)(eeprom_var *v, int address);
	bool (*read_eeprom_var)(eeprom_var *v, int address);
	bool (*store_eeprom_var_batch)(eeprom_var *v, int base_addr, int count);
	bool (*read_eeprom_var_batch)(eeprom_var *v, int base_addr, int count);

	// Custom config: register a settings page that appears in VESC Tool.
	// get_cfg serializes current/default settings, set_cfg applies them,
	// get_cfg_xml returns the config XML. clear removes registered configs.
	void (*conf_custom_add_config)(
			int (*get_cfg)(uint8_t *data, bool is_default),
			bool (*set_cfg)(uint8_t *data),
			int (*get_cfg_xml)(uint8_t **data));
	void (*conf_custom_clear_configs)(void);

	// Wi-Fi: connection state and network management. Sending data to the app
	// over Wi-Fi goes through send_app_data (routed to the active link).
	bool (*wifi_is_connected)(void);       // connected to an AP (station mode)
	bool (*wifi_is_client_connected)(void);// a client is connected to our AP
	bool (*wifi_is_connecting)(void);
	void (*wifi_disconnect)(void);
	bool (*wifi_change_network)(const char *ssid, const char *password);
	bool (*wifi_reconnect_network)(void);
	bool (*wifi_disconnect_network)(void);
	bool (*wifi_set_auto_reconnect)(bool should_reconnect);
	bool (*wifi_get_auto_reconnect)(void);

	// CAN: more remote-device commands. handbrake current/relative, IO-board
	// digital/PWM outputs, power-switch board on/off, and a PID position
	// offset update. Same controller_id addressing as the can_set_* group.
	void (*can_set_handbrake)(uint8_t controller_id, float current);
	void (*can_set_handbrake_rel)(uint8_t controller_id, float current_rel);
	void (*can_io_board_set_output_digital)(int id, int channel, bool on);
	void (*can_io_board_set_output_pwm)(int id, int channel, float duty);
	void (*can_psw_switch)(int id, bool is_on, bool plot);
	void (*can_update_pid_pos_offset)(int id, float angle_now, bool store);
	// Set remote input state (nunchuk/joystick + buttons) on a motor
	// controller over CAN. js_x/js_y are 0..255 (128 = centre); bt_c/bt_z are
	// the C/Z buttons; acc_* are raw accelerometer counts. Sent as a
	// COMM_SET_CHUCK_DATA packet, processed with no reply.
	void (*can_set_chuck_data)(uint8_t controller_id, int js_x, int js_y,
			bool bt_c, bool bt_z, int acc_x, int acc_y, int acc_z);

	// GPIO: configure/read/write a pin directly. mode: 0=input, 1=output
	// (input+output), 2=open-drain. pull: 0=none, 1=pull-up, 2=pull-down.
	// Invalid pins are ignored (write) or read back false.
	void (*gpio_configure)(int pin, int mode, int pull);
	void (*gpio_write)(int pin, bool state);
	bool (*gpio_read)(int pin);

	// I2C: single combined write-then-read transaction on the shared bus
	// (bus is brought up on first use). Pass write=NULL/wlen=0 for read-only,
	// read=NULL/rlen=0 for write-only. Returns 0 (ESP_OK) on success.
	int (*i2c_tx_rx)(uint8_t addr, const uint8_t *write, size_t wlen,
			uint8_t *read, size_t rlen);

	// GNSS: latest decoded NMEA state (position/speed/satellites) and a short
	// fix-type string ("No fix"/"2D"/"3D"/...). Present only when a GNSS
	// receiver is configured; state fields are zero until the first fix.
	nmea_state_t* (*gnss_get_state)(void);
	const char* (*gnss_fix_type)(void);

	// BMS: read the tracked pack values, broadcast this device's BMS status
	// on CAN, and register a handler for incoming BMS commands (cmd is a
	// COMM_PACKET_ID value). The handler pointer is translated to its IROM
	// alias before being stored.
	volatile bms_values* (*bms_get_values)(void);
	void (*bms_send_status_can)(void);
	void (*bms_set_cmd_handler)(void (*handler)(int cmd, int param1, int param2));

	// Wi-Fi: send raw bytes over the active TCP link to the connected local
	// client or the hub (bypasses VESC-protocol packet framing). For sending
	// app data prefer send_app_data; there is no arbitrary outbound-socket API.
	void (*wifi_send_raw_local)(unsigned char *data, unsigned int len);
	void (*wifi_send_raw_hub)(unsigned char *data, unsigned int len);

	// MQTT client (esp-mqtt backed). Typical use: mqtt_init(&cfg) -> handle,
	// mqtt_set_event_handler(handle, cb), mqtt_start(handle), then publish/
	// subscribe; mqtt_destroy when done. publish/subscribe/unsubscribe return
	// the message id (>=0) or -1 on failure. Reconnect, keepalive, QoS and TLS
	// (mqtts://) are handled by esp-mqtt. NULL on firmware built without the
	// mqtt component - check mqtt_init for NULL before use.
	void* (*mqtt_init)(const mqtt_config *cfg);
	bool  (*mqtt_start)(void *client);
	bool  (*mqtt_stop)(void *client);
	int   (*mqtt_publish)(void *client, const char *topic, const uint8_t *data, int len, int qos, bool retain);
	int   (*mqtt_subscribe)(void *client, const char *topic, int qos);
	int   (*mqtt_unsubscribe)(void *client, const char *topic);
	void  (*mqtt_destroy)(void *client);
	void  (*mqtt_set_event_handler)(void *client, void (*cb)(void *client, const mqtt_event *ev));

	// ESP-NOW: connectionless peer-to-peer over Wi-Fi (no access point needed).
	// Bring up with espnow_start, add peer MACs, then send/receive. MACs are
	// 6-byte arrays. add_peer rate < 0 uses the default rate. espnow_send
	// returns 0 (ESP_OK) once queued; delivery is best-effort. The rx callback
	// fires for every received frame (src MAC, payload, RSSI); its pointers are
	// valid only during the call. Shared with the lisp esp-now-* extensions, so
	// both can run at once. NULL on firmware without Wi-Fi (ESP32-P4).
	bool (*espnow_start)(void);
	bool (*espnow_add_peer)(const uint8_t *mac, int rate);
	bool (*espnow_del_peer)(const uint8_t *mac);
	int  (*espnow_send)(const uint8_t *mac, const uint8_t *data, int len);
	void (*espnow_set_rx_callback)(void (*cb)(const uint8_t *src, const uint8_t *data, int len, int rssi));

	// BLE GATT server (peripheral). Requires the device to be in BLE scripting
	// mode (BLE_MODE_SCRIPTING) - this is mutually exclusive with the normal
	// VESC Tool BLE link. Coexists with the lisp ble-* extensions. Typical use:
	// ble_set_name, ble_add_service (once per service), ble_start; then notify
	// clients with ble_attr_set_value and receive writes via the callback.
	// UUIDs and perm/prop bitmasks use the ble_uuid / VESC_BLE_* definitions.
	// ble_add_service returns the number of created handles (or -1) and fills
	// handles[] up to handles_cap: service handle first, then each
	// characteristic followed by its descriptors, in definition order. The rx
	// callback's data pointer is valid only during the call. All NULL on
	// firmware without BLE (ESP32-P4).
	bool (*ble_start)(void);
	bool (*ble_started)(void);
	bool (*ble_set_name)(const char *name);
	bool (*ble_update_adv)(bool use_raw, const uint8_t *adv, int adv_len,
			const uint8_t *scan_rsp, int scan_rsp_len);
	int  (*ble_add_service)(const ble_uuid *uuid, const ble_chr_def *chrs,
			int chr_count, uint16_t *handles, int handles_cap);
	bool (*ble_remove_service)(uint16_t service_handle);
	int  (*ble_attr_get_value)(uint16_t handle, uint8_t *out, int out_cap);
	bool (*ble_attr_set_value)(uint16_t handle, const uint8_t *data, int len);
	void (*ble_set_write_callback)(void (*cb)(uint16_t handle, const uint8_t *data, int len));

	// Standard BLE app link (the normal VESC Tool / phone connection, used in
	// the non-scripting BLE modes). ble_app_connected reports whether a central
	// is connected and ble_app_mtu the negotiated MTU. Register a callback to be
	// notified on connect (true) / disconnect (false) - it runs in the BLE stack
	// context, so keep it short. Data over this link uses send_app_data /
	// set_app_data_handler. Inert on ESP32-P4 (connected=false, mtu=0).
	bool (*ble_app_connected)(void);
	int  (*ble_app_mtu)(void);
	void (*ble_app_set_conn_callback)(void (*cb)(bool connected));
	void (*get_ble_mac)(uint8_t *buf);

	// Accessory: RGB LED
	bool (*rgbled_init)(int pin, unsigned int timing_preset);
	void (*rgbled_deinit)(int pin);
	void (*rgbled_update)(int pin, uint8_t *data, size_t size);
} vesc_c_if;

typedef struct {
	void (*stop_fun)(void *arg);
	void *arg;
	uint32_t base_addr;
} lib_info;

// System tick rate. Can be used to convert system ticks to time
#define SYSTEM_TICK_RATE_HZ 1000

/*
 * Address of the firmware-side C interface table. It must match the address
 * of the .libif section in main/linker_libif_<target>.ld for the target the
 * firmware (and the native library) is built for.
 *
 * The firmware build picks the target up from sdkconfig automatically. When
 * building a native library out of tree, define the CONFIG_IDF_TARGET_*
 * macro matching the hardware you are building for, e.g.
 * -DCONFIG_IDF_TARGET_ESP32C3=1. A library only works on the target it was
 * built for.
 */
#if defined(__has_include)
#if __has_include("sdkconfig.h")
#include "sdkconfig.h"
#endif
#endif

#if defined(CONFIG_IDF_TARGET_ESP32C3)
#define VESC_IF		((vesc_c_if*)(0x3FCDBE00))
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
#define VESC_IF		((vesc_c_if*)(0x3FCE8800))
#elif defined(CONFIG_IDF_TARGET_ESP32C6)
#define VESC_IF		((vesc_c_if*)(0x4087B800))
#elif defined(CONFIG_IDF_TARGET_ESP32P4)
#define VESC_IF		((vesc_c_if*)(0x4FF3A000))
#else
#error "Unknown ESP target. Define CONFIG_IDF_TARGET_ESP32C3, -S3, -C6 or -P4 when building a native library."
#endif

// Put this at the beginning of your source file
#define HEADER		volatile int __attribute__((__section__(".program_ptr"))) prog_ptr;

// Init function
#define INIT_FUN	bool __attribute__((__section__(".init_fun"))) init

// Put this at the start of the init function. The version check reads the
// first table slot only - safe even when the firmware carries a different
// interface layout.
#define INIT_START	(void)prog_ptr; \
					if (VESC_IF->if_version != VESC_C_IF_VERSION) { \
						return false; \
					}

// Address of this program in memory
#define PROG_ADDR	((uint32_t)&prog_ptr)

// The argument that was set in the init function (same as the one you get in stop_fun)
#define ARG			(*VESC_IF->get_arg(PROG_ADDR))

extern volatile int prog_ptr;

#endif  // VESC_C_IF_H
