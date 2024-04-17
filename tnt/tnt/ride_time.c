// Copyright 2024 Michael Silberstein
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

#include "ride_time.h"

void ride_timer(RideTimeData *ridetime, RuntimeData *rt){
	if(ridetime->run_flag) { //First trigger run flag and reset last ride time
		ridetime->ride_time += rt->current_time - ridetime->last_ride_time;
	}
	ridetime->run_flag = true;
	ridetime->last_ride_time = rt->current_time;
}


void rest_timer(RideTimeData *ridetime, RuntimeData *rt){
	if(!ridetime->run_flag) { //First trigger run flag and reset last rest time
		ridetime->rest_time += rt->current_time - ridetime->last_rest_time;
	}
	ridetime->run_flag = false;
	ridetime->last_rest_time = rt->current_time;
}
