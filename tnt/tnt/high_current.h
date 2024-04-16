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

#pragma once

	struct {
	bool traction_control,
	float wheelslip_timeron,
	float wheelslip_timeroff,
	float wheelslip_accelstartval,
	bool wheelslip_highaccelon1,
	bool wheelslip_highaccelon2,
	float wheelslip_lasterpm,
	float wheelslip_erpm,
	} TractionData;
