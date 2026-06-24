/* Copyright (C) 2025 arvern project

   This file is part of Embench and was formerly part of the Bristol/Embecosm
   Embedded Benchmark Suite.

   SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef BOARDSUPPORT_H
#define BOARDSUPPORT_H

// CPU frequency in MHz
#define CPU_MHZ 1

// Peripheral register definitions for arvern
#define P0_OUT0  (*(volatile unsigned int *) 0x10040000)  // Character output
#define P0_OUT1  (*(volatile unsigned int *) 0x10040004)  // Character ready signal
#define P0_IN15  (*(volatile unsigned int *) 0x1004003C)  // Time counter
#define P1_OUT0  (*(volatile unsigned int *) 0x10041000)  // Timing marker (1=start, 0=end)
#define P1_OUT1  (*(volatile unsigned int *) 0x10041004)  // Benchmark result (1=pass, 0=fail)
#define P1_OUT2  (*(volatile unsigned int *) 0x10041008)  // Test-done, pass/fail result available

#endif // BOARDSUPPORT_H
