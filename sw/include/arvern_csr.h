/*----------------------------------------------------------------------------
 *          _    _           Family:    aRVern
 *         / \__/ \          File:      arvern_csr.h
 *        /   /\   \         --------------------------------------------
 *    ===/   /=========      Copyright: (c) 2026, aRVern-dev
 *      /   / RV \   \       Contact:   arvernsilicon@gmail.com
 *     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Full license text is available in the LICENSE file at the repository root.
 *----------------------------------------------------------------------------
 * CSR access for the aRVern core: read / write / set / clear macros, the
 * aRVern-specific CSR numbers and the interrupt-related bit fields.
 * Reference: doc/traps_and_interrupts.md, doc/software_guide.md.
 *----------------------------------------------------------------------------*/
#ifndef ARVERN_CSR_H
#define ARVERN_CSR_H

#include <stdint.h>

/*---------------------------------------------------------------------------
 * Access macros: the CSR is a name (mstatus) or a number (0x744)
 *---------------------------------------------------------------------------*/
#define ARV_STR_(x)  #x
#define ARV_STR(x)   ARV_STR_(x)

#define arv_csr_read(csr)        ({ uint32_t v_; __asm__ volatile ("csrr %0, " ARV_STR(csr) : "=r"(v_)); v_; })
#define arv_csr_write(csr, val)  __asm__ volatile ("csrw " ARV_STR(csr) ", %0" :: "rK"((uint32_t)(val)) : "memory")
#define arv_csr_set(csr, val)    __asm__ volatile ("csrs " ARV_STR(csr) ", %0" :: "rK"((uint32_t)(val)) : "memory")
#define arv_csr_clear(csr, val)  __asm__ volatile ("csrc " ARV_STR(csr) ", %0" :: "rK"((uint32_t)(val)) : "memory")
#define arv_csr_swap(csr, val)   ({ uint32_t v_; __asm__ volatile ("csrrw %0, " ARV_STR(csr) ", %1" : "=r"(v_) : "rK"((uint32_t)(val)) : "memory"); v_; })

/*---------------------------------------------------------------------------
 * CSR numbers not known to every assembler
 *---------------------------------------------------------------------------*/
#define CSR_MSTATUSH      0x310
#define CSR_MNSCRATCH     0x740         /* Smrnmi */
#define CSR_MNEPC         0x741
#define CSR_MNCAUSE       0x742
#define CSR_MNSTATUS      0x744
#define CSR_MARV_NMVEC    0x7FD         /* RNMI / double-trap vector */
#define CSR_MARV_ESTAT    0x7FE         /* data-bus error status     */
#define CSR_MARV_CTL      0x7FF         /* core feature control      */
#define CSR_MARV_EPC      0xFFC         /* PC of the faulting access */
#define CSR_MARV_EADDR    0xFFD         /* address of the fault      */

/*---------------------------------------------------------------------------
 * Fields
 *---------------------------------------------------------------------------*/
#define MSTATUS_MIE       (1u << 3)
#define MSTATUS_MPIE      (1u << 7)
#define MSTATUSH_MDT      (1u << 10)
#define MNSTATUS_NMIE     (1u << 3)

/* mie / mip: standard bits and the 16 platform interrupts */
#define MIP_SSI           (1u << 1)
#define MIP_MSI           (1u << 3)
#define MIP_STI           (1u << 5)
#define MIP_MTI           (1u << 7)
#define MIP_SEI           (1u << 9)
#define MIP_MEI           (1u << 11)
#define MIP_PLATFORM(n)   (1u << (16u + (n)))   /* irq_platform_i[n], n = 0..15 */

/* mcause */
#define MCAUSE_IRQ        (1u << 31)
#define MCAUSE_CODE_Msk   0x1Fu
#define IRQ_M_SOFT        3u
#define IRQ_M_TIMER       7u
#define IRQ_M_EXT         11u
#define IRQ_PLATFORM(n)   (16u + (n))

/* mncause */
#define MNCAUSE_RNMI      (1u << 31)    /* clear: a double-trap divert, [4:0] = cause */
#define MNCAUSE_PIN       0x80000002u   /* nmi_i                                     */
#define MNCAUSE_BUS_ERROR 0x80000003u   /* data-bus error                            */

/* marv_estat */
#define MARV_ESTAT_VALID       (1u << 0)
#define MARV_ESTAT_STORE       (1u << 1)
#define MARV_ESTAT_OVERRUN     (1u << 2)
#define MARV_ESTAT_RESTARTABLE (1u << 3)
#define MARV_ESTAT_UOP         (1u << 4)

/*---------------------------------------------------------------------------
 * Small helpers
 *---------------------------------------------------------------------------*/
static inline void arv_irq_global_enable(void)  { arv_csr_set(mstatus, MSTATUS_MIE); }
static inline void arv_irq_global_disable(void) { arv_csr_clear(mstatus, MSTATUS_MIE); }

/* Disable interrupts and return the previous state, for arv_irq_restore() */
static inline uint32_t arv_irq_save(void)
{
    uint32_t v;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(v) :: "memory");
    return v & MSTATUS_MIE;
}

static inline void arv_irq_restore(uint32_t state)
{
    arv_csr_set(mstatus, state & MSTATUS_MIE);
}

static inline void arv_wfi(void) { __asm__ volatile ("wfi" ::: "memory"); }

#endif /* ARVERN_CSR_H */
