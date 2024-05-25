// Copyright 2024 Michael Silberstein
// This code was originally written by the authors of Float package and 
// modifed for this package
//
// This file is part of the VESC package.
//
// This VESC package is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This VESC package is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

#include "utils_tnt.h"
#include <math.h>

float roll_erpm_scale(const tnt_config *config, float abs_erpm){ 
	float erpmscale = lerp(config->roll_lowerpm, config->roll_higherpm, 0, config->roll_maxscale/100, abs_erpm);
	float sign_erpmscale = sign(erpmscale);
	erpmscale = min(max(fabsf(erpmscale), 0), config->yaw_maxscale/100) * sign_erpmscale;
	return erpmscale;
}

