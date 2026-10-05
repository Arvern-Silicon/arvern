/*----------------------------------------------------------------------------
 *          _    _           Family:    aRVern
 *         / \__/ \          File:      arvern_irq.h
 *        /   /\   \         --------------------------------------------
 *    ===/   /=========      Copyright: (c) 2026, aRVern-dev
 *      /   / RV \   \       Contact:   arvernsilicon@gmail.com
 *     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Full license text is available in the LICENSE file at the repository root.
 *----------------------------------------------------------------------------
 * Trap and interrupt layer for bare-metal M-mode firmware on aRVern: one trap
 * entry (direct mode) and one RNMI entry, both dispatching to C handlers
 * registered per cause.
 *
 *   arv_irq_init()            install the entries (mtvec, marv_nmvec, NMI stack)
 *   arv_irq_attach(n, fn)     handler for interrupt cause n (3, 7, 11, 16..31)
 *   arv_irq_enable(n) ...     mie bits; arv_irq_global_enable() (arvern_csr.h)
 *   arv_exc_attach(n, fn)     handler for synchronous exception cause n
 *   arv_nmi_attach(fn)        handler for RNMIs and double-trap diverts
 *
 * Handlers run with interrupts masked and mstatush.MDT set: a trap inside a
 * handler is a double trap, diverted to the NMI handler with the cause in
 * mncause[4:0] (the default NMI handler records it and stops).
 *
 * Boot order: the startup code must arm mnstatus.NMIE (csrsi 0x744, 8) and then
 * clear mstatush.MDT before the first trap; arv_irq_boot() does both for code
 * that has not.
 *----------------------------------------------------------------------------*/
#ifndef ARVERN_IRQ_H
#define ARVERN_IRQ_H

#include <stdbool.h>
#include <stdint.h>
#include "arvern_csr.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Interrupt handler: the cause code (3, 7, 11, 16..31) */
typedef void (*arv_irq_handler_t)(uint32_t cause);

/* Exception handler: returns the PC to resume at (mepc + instruction length to
 * skip the faulting instruction, mepc to retry it) */
typedef uint32_t (*arv_exc_handler_t)(uint32_t cause, uint32_t mepc, uint32_t mtval);

/* RNMI handler: mncause and mnepc; returns the PC to resume at (mnepc in
 * general, see doc/software_guide.md "Data-Bus Errors") */
typedef uint32_t (*arv_nmi_handler_t)(uint32_t mncause, uint32_t mnepc);

/* Last unhandled trap, for a debugger (also the state the default handlers stop in) */
typedef struct {
    uint32_t cause;             /* mcause, or mncause for an NMI      */
    uint32_t epc;               /* mepc / mnepc                       */
    uint32_t tval;              /* mtval, or marv_eaddr for a bus error */
    uint32_t nmi;               /* 1 when it came through the NMI entry */
} arv_trap_record_t;

extern volatile arv_trap_record_t arv_trap_last;

/* Arm NMIE, then clear MDT (Smdbltrp boot order); idempotent */
static inline void arv_irq_boot(void)
{
    arv_csr_set(CSR_MNSTATUS, MNSTATUS_NMIE);
    arv_csr_write(CSR_MSTATUSH, 0);
}

/* Install the trap and NMI entries; all handlers default to "record and stop" */
void arv_irq_init(void);

void arv_irq_attach(unsigned cause, arv_irq_handler_t fn);
void arv_exc_attach(unsigned cause, arv_exc_handler_t fn);
void arv_nmi_attach(arv_nmi_handler_t fn);

static inline void arv_irq_enable(unsigned cause)  { arv_csr_set(mie, 1u << cause); }
static inline void arv_irq_disable(unsigned cause) { arv_csr_clear(mie, 1u << cause); }

/* Platform pending bits (mip[31:16]) are latched: clear the source in the
 * device first, then the bit */
static inline void arv_irq_clear_pending(unsigned cause) { arv_csr_clear(mip, 1u << cause); }
static inline bool arv_irq_pending(unsigned cause)       { return (arv_csr_read(mip) >> cause) & 1u; }

#ifdef __cplusplus
}
#endif

#endif /* ARVERN_IRQ_H */
