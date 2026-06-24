
//=============================================================================
// PERIPHERALS REGISTER DEFINITIONS
//=============================================================================

//----------------------------------------------------------
// PERIPHERAL #1
//----------------------------------------------------------
#define  P1_OUT0       (*(volatile unsigned int *) 0x10040000)
#define  P1_OUT1       (*(volatile unsigned int *) 0x10040004)
#define  P1_OUT2       (*(volatile unsigned int *) 0x10040008)
#define  P1_OUT3       (*(volatile unsigned int *) 0x1004000C)
#define  P1_OUT4       (*(volatile unsigned int *) 0x10040010)
#define  P1_OUT5       (*(volatile unsigned int *) 0x10040014)
#define  P1_OUT6       (*(volatile unsigned int *) 0x10040018)
#define  P1_OUT7       (*(volatile unsigned int *) 0x1004001C)

#define  P1_IN0        (*(volatile unsigned int *) 0x10040020)
#define  P1_IN1        (*(volatile unsigned int *) 0x10040024)
#define  P1_IN2        (*(volatile unsigned int *) 0x10040028)
#define  P1_IN3        (*(volatile unsigned int *) 0x1004002C)
#define  P1_IN4        (*(volatile unsigned int *) 0x10040030)
#define  P1_IN5        (*(volatile unsigned int *) 0x10040034)
#define  P1_IN6        (*(volatile unsigned int *) 0x10040038)
#define  P1_IN7        (*(volatile unsigned int *) 0x1004003C)

//----------------------------------------------------------
// PERIPHERAL #2
//----------------------------------------------------------
#define  P2_OUT0       (*(volatile unsigned int *) 0x10041000)
#define  P2_OUT1       (*(volatile unsigned int *) 0x10041004)
#define  P2_OUT2       (*(volatile unsigned int *) 0x10041008)
#define  P2_OUT3       (*(volatile unsigned int *) 0x1004100C)
#define  P2_OUT4       (*(volatile unsigned int *) 0x10041010)
#define  P2_OUT5       (*(volatile unsigned int *) 0x10041014)
#define  P2_OUT6       (*(volatile unsigned int *) 0x10041018)
#define  P2_OUT7       (*(volatile unsigned int *) 0x1004101C)

#define  P2_IN0        (*(volatile unsigned int *) 0x10041020)
#define  P2_IN1        (*(volatile unsigned int *) 0x10041024)
#define  P2_IN2        (*(volatile unsigned int *) 0x10041028)
#define  P2_IN3        (*(volatile unsigned int *) 0x1004102C)
#define  P2_IN4        (*(volatile unsigned int *) 0x10041030)
#define  P2_IN5        (*(volatile unsigned int *) 0x10041034)
#define  P2_IN6        (*(volatile unsigned int *) 0x10041038)
#define  P2_IN7        (*(volatile unsigned int *) 0x1004103C)


//=============================================================================
// MACROS
//=============================================================================


//=============================================================================
// FUNCTIONS
//=============================================================================

// Replace printf statements with custom one
#include "cprintf.h"
#define   printf  cprintf

