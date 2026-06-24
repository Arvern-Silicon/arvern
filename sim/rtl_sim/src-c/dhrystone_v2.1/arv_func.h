//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      arv_func
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------

//=============================================================================
// PERIPHERALS REGISTER DEFINITIONS
//=============================================================================

//----------------------------------------------------------
// PERIPHERAL #0
//----------------------------------------------------------
#define  P0_OUT0       (*(volatile unsigned int *) 0x10040000)     // Used by printf
#define  P0_OUT1       (*(volatile unsigned int *) 0x10040004)     // Used by printf
#define  P0_OUT2       (*(volatile unsigned int *) 0x10040008)
#define  P0_OUT3       (*(volatile unsigned int *) 0x1004000C)
#define  P0_OUT4       (*(volatile unsigned int *) 0x10040010)
#define  P0_OUT5       (*(volatile unsigned int *) 0x10040014)
#define  P0_OUT6       (*(volatile unsigned int *) 0x10040018)
#define  P0_OUT7       (*(volatile unsigned int *) 0x1004001C)

#define  P0_IN0        (*(volatile unsigned int *) 0x10040020)
#define  P0_IN1        (*(volatile unsigned int *) 0x10040024)
#define  P0_IN2        (*(volatile unsigned int *) 0x10040028)
#define  P0_IN3        (*(volatile unsigned int *) 0x1004002C)
#define  P0_IN4        (*(volatile unsigned int *) 0x10040030)
#define  P0_IN5        (*(volatile unsigned int *) 0x10040034)
#define  P0_IN6        (*(volatile unsigned int *) 0x10040038)
#define  P0_IN7        (*(volatile unsigned int *) 0x1004003C)

//----------------------------------------------------------
// PERIPHERAL #2
//----------------------------------------------------------
#define  P1_OUT0       (*(volatile unsigned int *) 0x10041000)
#define  P1_OUT1       (*(volatile unsigned int *) 0x10041004)
#define  P1_OUT2       (*(volatile unsigned int *) 0x10041008)
#define  P1_OUT3       (*(volatile unsigned int *) 0x1004100C)
#define  P1_OUT4       (*(volatile unsigned int *) 0x10041010)
#define  P1_OUT5       (*(volatile unsigned int *) 0x10041014)
#define  P1_OUT6       (*(volatile unsigned int *) 0x10041018)
#define  P1_OUT7       (*(volatile unsigned int *) 0x1004101C)

#define  P1_IN0        (*(volatile unsigned int *) 0x10041020)
#define  P1_IN1        (*(volatile unsigned int *) 0x10041024)
#define  P1_IN2        (*(volatile unsigned int *) 0x10041028)
#define  P1_IN3        (*(volatile unsigned int *) 0x1004102C)
#define  P1_IN4        (*(volatile unsigned int *) 0x10041030)
#define  P1_IN5        (*(volatile unsigned int *) 0x10041034)
#define  P1_IN6        (*(volatile unsigned int *) 0x10041038)
#define  P1_IN7        (*(volatile unsigned int *) 0x1004103C)


//=============================================================================
// MACROS
//=============================================================================

#define SetPort( state ) P1_OUT3  = (state)

#define START_TIME       P1_OUT0  = 0x00000001
#define END_TIME         P1_OUT0  = 0x00000000

#define DHRYSTONE_DONE   P1_OUT1  = 0x00000001


//=============================================================================
// FUNCTIONS
//=============================================================================

// Replace printf statements with custom one
#include "mylib/cprintf.h"
#define   printf  cprintf
