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

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include "arv_func.h"

//--------------------------------------------------//
//                   Cheap Malloc                   //
//--------------------------------------------------//

#define HEAP_SIZE  256  // 256B heap

static uint8_t heap[HEAP_SIZE];
static size_t heap_offset = 0;

// Aligns size to nearest multiple of 4
static inline size_t align4(size_t n) {
    return (n + 3) & ~((size_t)3);
}

// Minimal malloc
void * emalloc(size_t nbytes) {
    nbytes = align4(nbytes);

    if (heap_offset + nbytes > HEAP_SIZE) {
        return NULL;  // Out of memory
    }

    void *ptr = &heap[heap_offset];
    heap_offset += nbytes;

    return ptr;
}

//--------------------------------------------------//
//                 putChar function                 //
//            (Send a byte to the Port-1)           //
//--------------------------------------------------//
//int putchar (int txdata) {
void tty_putc (char txdata) {

  // Write the output character to the Port-1
  P0_OUT0  = txdata;

  // Pulse Port-2[0] to signal new byte
  P0_OUT1  = 1;
  P0_OUT1  = 0;

}
