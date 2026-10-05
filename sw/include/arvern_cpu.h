/*----------------------------------------------------------------------------
 *          _    _           Family:    aRVern
 *         / \__/ \          File:      arvern_cpu.h
 *        /   /\   \         --------------------------------------------
 *    ===/   /=========      Copyright: (c) 2026, aRVern-dev
 *      /   / RV \   \       Contact:   arvernsilicon@gmail.com
 *     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Full license text is available in the LICENSE file at the repository root.
 *----------------------------------------------------------------------------
 * Build discovery: identify the core (marchid) and decode misa and marv_cfg
 * into the synthesized configuration. marv_cfg is read only once marchid has
 * identified aRVern (on another core 0xFFF would trap).
 * Reference: doc/software_guide.md "Build Discovery and aRVern CSRs".
 *----------------------------------------------------------------------------*/
#ifndef ARVERN_CPU_H
#define ARVERN_CPU_H

#include <stdbool.h>
#include <stdint.h>
#include "arvern_csr.h"

#define ARV_MARCHID        0x36u
#define ARV_MVENDORID      0x08FBu
#define CSR_MARV_CFG       0xFFF

/* misa extension bits */
#define MISA_EXT(c)        (1u << ((c) - 'A'))

typedef struct {
    bool     is_arvern;         /* marchid = 0x36; every field below is valid only then */
    uint32_t mimpid;            /* {major, minor, patch, 0}                             */
    uint32_t misa;
    uint32_t marv_cfg;
    bool     rv32e;             /* 16 integer registers                                 */
    uint8_t  m_level;           /* 0 none, 1 Zmmul (multiply only), 2 full M            */
    uint8_t  mul_type;          /* 0 none, 1 single-cycle, 2 four-cycle, 3 sixteen-cycle */
    uint8_t  div_type;          /* 0 none, 1 radix-8, 2 radix-4, 3 radix-2              */
    uint8_t  b_level;           /* B_EXTENSION 0-4 (4: Zbc)                             */
    uint8_t  c_level;           /* C_EXTENSION 0-4                                      */
    bool     su_mode;           /* S and U modes                                        */
    bool     zicntr;            /* cycle / time / instret                               */
    uint8_t  zihpm_nr;          /* HPM counters                                         */
    uint8_t  pmp_nr;            /* 0, 4, 8 or 16 entries                                */
    bool     debug;             /* external debug (Debug Module)                        */
    uint8_t  dm_triggers;       /* Sdtrig triggers                                      */
    bool     ccsr;              /* custom CSR interface                                 */
} arv_cpu_info_t;

static inline arv_cpu_info_t arv_cpu_probe(void)
{
    arv_cpu_info_t i = {0};
    i.is_arvern = (arv_csr_read(marchid) == ARV_MARCHID);
    i.misa      = arv_csr_read(misa);
    if (!i.is_arvern)
        return i;
    uint32_t c    = arv_csr_read(CSR_MARV_CFG);
    i.mimpid      = arv_csr_read(mimpid);
    i.marv_cfg    = c;
    i.rv32e       = (i.misa & MISA_EXT('E')) != 0u;
    i.mul_type    = (uint8_t) ((c >> 18) & 0x3u);
    i.div_type    = (uint8_t) ((c >> 16) & 0x3u);
    i.m_level     = (i.misa & MISA_EXT('M')) ? 2u : (i.mul_type ? 1u : 0u);
    i.b_level     = (uint8_t) ((c >> 20) & 0x7u);
    i.c_level     = (uint8_t) ((c >> 24) & 0x7u);
    i.zihpm_nr    = (uint8_t) ((c >> 12) & 0xFu);
    i.dm_triggers = (uint8_t) ((c >> 8) & 0xFu);
    i.pmp_nr      = (uint8_t) (((c >> 6) & 0x3u) ? (2u << ((c >> 6) & 0x3u)) : 0u);
    i.zicntr      = ((c >> 3) & 1u) != 0u;
    i.su_mode     = ((c >> 2) & 1u) != 0u;
    i.debug       = ((c >> 1) & 1u) != 0u;
    i.ccsr        = (c & 1u) != 0u;
    return i;
}

#endif /* ARVERN_CPU_H */
