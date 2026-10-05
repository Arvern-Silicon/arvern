/*----------------------------------------------------------------------------
 *          _    _           Family:    aRVern
 *         / \__/ \          File:      arvern_irq.c
 *        /   /\   \         --------------------------------------------
 *    ===/   /=========      Copyright: (c) 2026, aRVern-dev
 *      /   / RV \   \       Contact:   arvernsilicon@gmail.com
 *     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Full license text is available in the LICENSE file at the repository root.
 *----------------------------------------------------------------------------
 * Handler tables and C dispatch for arvern_trap.S.
 *----------------------------------------------------------------------------*/
#include "arvern_irq.h"

#ifndef ARV_NMI_STACK_WORDS
#define ARV_NMI_STACK_WORDS 64u
#endif

extern void arv_trap_entry(void);
extern void arv_nmi_entry(void);

volatile arv_trap_record_t arv_trap_last;

static arv_irq_handler_t irq_table[32];
static arv_exc_handler_t exc_table[32];
static arv_nmi_handler_t nmi_handler;
static uint32_t          nmi_stack[ARV_NMI_STACK_WORDS] __attribute__((aligned(16)));

static void record(uint32_t cause, uint32_t epc, uint32_t tval, uint32_t nmi)
{
    arv_trap_last.cause = cause;
    arv_trap_last.epc   = epc;
    arv_trap_last.tval  = tval;
    arv_trap_last.nmi   = nmi;
}

/* An unhandled trap stops here; the record says which one */
static void stop(void)
{
    for (;;)
        __asm__ volatile ("wfi");
}

void arv_irq_init(void)
{
    arv_irq_boot();
    arv_csr_write(mie, 0);
    arv_csr_write(CSR_MNSCRATCH, (uint32_t) &nmi_stack[ARV_NMI_STACK_WORDS]);
    arv_csr_write(CSR_MARV_NMVEC, (uint32_t) &arv_nmi_entry);
    arv_csr_write(mtvec, (uint32_t) &arv_trap_entry);       /* direct mode */
}

void arv_irq_attach(unsigned cause, arv_irq_handler_t fn) { if (cause < 32u) irq_table[cause] = fn; }
void arv_exc_attach(unsigned cause, arv_exc_handler_t fn) { if (cause < 32u) exc_table[cause] = fn; }
void arv_nmi_attach(arv_nmi_handler_t fn)                 { nmi_handler = fn; }

uint32_t arv_trap_dispatch(uint32_t mcause, uint32_t mepc, uint32_t mtval);
uint32_t arv_trap_dispatch(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    uint32_t code = mcause & MCAUSE_CODE_Msk;
    if (mcause & MCAUSE_IRQ) {
        if (irq_table[code]) {
            irq_table[code](code);
            return mepc;
        }
        arv_csr_clear(mie, 1u << code);                     /* unhandled: silence it */
        record(mcause, mepc, mtval, 0);
        return mepc;
    }
    if (exc_table[code])
        return exc_table[code](code, mepc, mtval);
    record(mcause, mepc, mtval, 0);
    stop();
    return mepc;
}

uint32_t arv_nmi_dispatch(uint32_t mncause, uint32_t mnepc);
uint32_t arv_nmi_dispatch(uint32_t mncause, uint32_t mnepc)
{
    if (nmi_handler)
        return nmi_handler(mncause, mnepc);

    /* Default: a data-bus error resumes past the access (evidence recorded and
     * cleared); a pin NMI resumes; a double-trap divert stops */
    if (mncause == MNCAUSE_BUS_ERROR) {
        record(mncause, arv_csr_read(CSR_MARV_EPC), arv_csr_read(CSR_MARV_EADDR), 1);
        arv_csr_write(CSR_MARV_ESTAT, MARV_ESTAT_VALID | MARV_ESTAT_OVERRUN);
        return mnepc;
    }
    if (mncause & MNCAUSE_RNMI)
        return mnepc;
    record(mncause, mnepc, 0, 1);
    stop();
    return mnepc;
}
