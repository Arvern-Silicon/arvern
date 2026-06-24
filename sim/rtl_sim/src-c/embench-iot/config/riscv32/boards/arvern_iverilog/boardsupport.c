/* Copyright (C) 2025 arvern project

   This file is part of Embench and was formerly part of the Bristol/Embecosm
   Embedded Benchmark Suite.

   SPDX-License-Identifier: GPL-3.0-or-later */

#include <support.h>
#include "boardsupport.h"

// Initialize the board (called once at startup)
void
initialise_board ()
{
  // No special initialization needed for arvern
  __asm__ volatile ("nop" : : : "memory");
}

// Start timing trigger (called before benchmark timing begins)
void __attribute__ ((noinline)) __attribute__ ((externally_visible))
start_trigger ()
{
  // Set P1_OUT0 to signal start of timing measurement
  P1_OUT0 = 1;
}

// Stop timing trigger (called after benchmark timing ends)
void __attribute__ ((noinline)) __attribute__ ((externally_visible))
stop_trigger ()
{
  // Clear P1_OUT0 to signal end of timing measurement
  P1_OUT0 = 0;
}
