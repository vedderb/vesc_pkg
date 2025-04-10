// This file is autogenerated by VESC Tool

#ifndef CONFPARSER_H_
#define CONFPARSER_H_

#include "datatypes.h"
#include <stdint.h>
#include <stdbool.h>

// Constants
#define TNT_CONFIG_SIGNATURE		3999863424

// Functions
int32_t confparser_serialize_tnt_config(uint8_t *buffer, const tnt_config *conf);
bool confparser_deserialize_tnt_config(const uint8_t *buffer, tnt_config *conf);
void confparser_set_defaults_tnt_config(tnt_config *conf);

// CONFPARSER_H_
#endif
