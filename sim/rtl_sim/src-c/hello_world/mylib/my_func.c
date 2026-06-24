
#include "my_func.h"

//--------------------------------------------------//
//                 putChar function                 //
//            (Send a byte to the Port-1)           //
//--------------------------------------------------//
//int putchar (int txdata) {
void tty_putc (char txdata) {

  // Write the output character to the Port-1
  P1_OUT0  = txdata;

  // Pulse Port-2[0] to signal new byte
  P1_OUT1  = 1;
  P1_OUT1  = 0;

}