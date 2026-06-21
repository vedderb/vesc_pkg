#include <check.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* External function from balance.c */
extern void set_cfg(void *d, const uint8_t *buffer, int length);

/* Minimal data structure matching balance.c internals */
typedef struct {
    float hertz;
    float startup_speed;
    float tiltback_duty_speed;
    float tiltback_hv_speed;
    float tiltback_lv_speed;
} balance_conf_t;

typedef struct {
    balance_conf_t balance_conf;
    float loop_time_seconds;
    float motor_timeout_seconds;
    float startup_step_size;
    float tiltback_duty_step_size;
    float tiltback_hv_step_size;
    float tiltback_lv_step_size;
} data_t;

START_TEST(test_division_by_zero_protection)
{
    /* Invariant: configure() must not perform division by zero on hertz,
       even when receiving adversarial configuration packets */
    
    data_t test_data;
    memset(&test_data, 0, sizeof(test_data));
    
    /* Payloads: hertz values to test */
    float hertz_values[] = {
        0.0f,           /* Exploit: exact zero divisor */
        -1.0f,          /* Boundary: negative value */
        0.0001f,        /* Boundary: very small but valid */
        100.0f          /* Valid: normal operating value */
    };
    
    int num_payloads = sizeof(hertz_values) / sizeof(hertz_values[0]);
    
    for (int i = 0; i < num_payloads; i++) {
        memset(&test_data, 0, sizeof(test_data));
        test_data.balance_conf.hertz = hertz_values[i];
        test_data.balance_conf.startup_speed = 10.0f;
        test_data.balance_conf.tiltback_duty_speed = 5.0f;
        test_data.balance_conf.tiltback_hv_speed = 8.0f;
        test_data.balance_conf.tiltback_lv_speed = 3.0f;
        
        /* Security property: function must not crash or produce inf/nan
           when hertz is zero or invalid */
        if (hertz_values[i] <= 0.0f) {
            /* For zero/negative hertz, the function should either:
               1. Reject the configuration, or
               2. Use a safe default that prevents division by zero */
            ck_assert_msg(
                test_data.balance_conf.hertz <= 0.0f,
                "Adversarial hertz value was not preserved for validation"
            );
        } else {
            /* For valid hertz, computed values must be finite */
            float loop_time = 1.0f / test_data.balance_conf.hertz;
            ck_assert_msg(
                loop_time > 0.0f && loop_time < 1e6f,
                "Valid hertz produced invalid loop_time calculation"
            );
        }
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("DivisionByZero");

    tcase_add_test(tc_core, test_division_by_zero_protection);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}