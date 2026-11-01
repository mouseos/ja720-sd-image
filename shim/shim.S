/*
 * JA720 Linux entry shim.
 *
 * The stock Besta loader loads the payload at 0x80000000 and calls the
 * entry point (payload offset 0x20, i.e. 0x80000020) as a C function
 * (BLX) with the MMU and caches configured for the BestaWin kernel.
 * The ARM Linux booting protocol instead requires, at zImage entry:
 *   - MMU off, instruction cache may be on, data cache off
 *   - r0 = 0, r1 = machine type (ignored with appended DTB),
 *     r2 = ATAG/DTB pointer (ignored with appended DTB)
 * This shim (32 bytes of header precede it) puts the CPU into that
 * state and branches to the zImage placed at payload offset 0x100
 * (physical 0x80000100).
 */
	.text
	.globl	_start
_start:
	/* Read SCTLR, clear MMU (bit 0), D-cache (bit 2), I-cache (bit 12) */
	mrc	p15, 0, r3, c1, c0, 0
	bic	r3, r3, #0x0001
	bic	r3, r3, #0x0004
	bic	r3, r3, #0x1000
	mcr	p15, 0, r3, c1, c0, 0

	/* Invalidate instruction and data caches and the TLB (ARM926) */
	mov	r3, #0
	mcr	p15, 0, r3, c7, c7, 0	/* invalidate I+D caches */
	mcr	p15, 0, r3, c8, c7, 0	/* invalidate I+D TLB */
	mcr	p15, 0, r3, c7, c10, 4	/* drain write buffer */

	/* Linux boot registers */
	mov	r0, #0
	mvn	r1, #0			/* r1 = 0xffffffff (invalid) */
	mov	r2, #0

	/* Jump to zImage */
	ldr	pc, =0x80000100
