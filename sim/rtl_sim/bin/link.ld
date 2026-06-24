/*--------------------------------------------------------------------------*
 *          _    _           Family:    aRVern System IPs                   *
 *         / \__/ \          Script:    link.ld                             *
 *        /   /\   \         --------------------------------------------   *
 *    ===/   /=========      Copyright: (c) 2026, aRVern-dev                *
 *      /   / RV \   \       Contact:   arvernsilicon@gmail.com             *
 *     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon   *
 *                                                                          *
 * SPDX-License-Identifier: BSD-3-Clause                                    *
 * Full license text is available in the LICENSE file at the repository root*
 *--------------------------------------------------------------------------*/
/* Linker script: code at 0x20000000, data/bss at 0x80000000. */

SECTIONS
{
  . = 0x20000000;           /* Load address */
  .text : { *(.text*) }
  . = 0x80000000;           /* Load address */
  .data : { *(.data*) }
  .bss  : { *(.bss*)  }
}
