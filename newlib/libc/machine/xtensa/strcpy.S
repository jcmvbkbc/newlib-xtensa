/* ANSI C standard library function strcpy.

   Copyright (c) 2001-2008 Tensilica Inc.

   Permission is hereby granted, free of charge, to any person obtaining
   a copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to
   permit persons to whom the Software is furnished to do so, subject to
   the following conditions:

   The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.  */

#include "xtensa-asm.h"

	.text
	.begin schedule
	.align	4
	.literal_position
	.global	strcpy
	.type	strcpy, @function
strcpy:
	leaf_entry sp
	/* a2 = dst, a3 = src */

	mov	a10, a2		// leave dst in return value register
	movi	a4, MASK0
	movi	a5, MASK1
	movi	a6, MASK2
	movi	a7, MASK3
	bbsi.l	a3, 0, .Lsrc1mod2
	bbsi.l	a3, 1, .Lsrc2mod4
.Lsrcaligned:

	/* Check if the destination is aligned.  */
	movi	a8, 3
	bnone	a10, a8, .Laligned

	j	.Ldstunaligned

.Lsrc1mod2: // src address is odd
	l8ui	a8, a3, 0	// get byte 0
	addi	a3, a3, 1	// advance src pointer
	s8i	a8, a10, 0	// store byte 0
	beqz	a8, 1f		// if byte 0 is zero
	addi	a10, a10, 1	// advance dst pointer
	bbci.l	a3, 1, .Lsrcaligned // if src is now word-aligned

.Lsrc2mod4: // src address is 2 mod 4
	l8ui	a8, a3, 0	// get byte 0
	/* 1-cycle interlock */
	s8i	a8, a10, 0	// store byte 0
	beqz	a8, 1f		// if byte 0 is zero
	l8ui	a8, a3, 1	// get byte 0
	addi	a3, a3, 2	// advance src pointer
	s8i	a8, a10, 1	// store byte 0
	addi	a10, a10, 2	// advance dst pointer
	bnez	a8, .Lsrcaligned
1:	leaf_return


/* dst is word-aligned; src is word-aligned.  */

	.align	4
#if XCHAL_HAVE_LOOPS
.Laligned:
	movi	a8, 0		// set up for the maximum loop count
	loop	a8, .Lz3	// loop forever (almost anyway)
	l32i	a8, a3, 0	// get word from src
	addi	a3, a3, 4	// advance src pointer
	bnone	a8, a4, .Lz0	// if byte 0 is zero
	bnone	a8, a5, .Lz1	// if byte 1 is zero
	bnone	a8, a6, .Lz2	// if byte 2 is zero
	s32i	a8, a10, 0	// store word to dst
	bnone	a8, a7, .Lz3	// if byte 3 is zero
	addi	a10, a10, 4	// advance dst pointer

#else /* !XCHAL_HAVE_LOOPS */

1:	addi	a10, a10, 4	// advance dst pointer
.Laligned:
	l32i	a8, a3, 0	// get word from src
	addi	a3, a3, 4	// advance src pointer
	bnone	a8, a4, .Lz0	// if byte 0 is zero
	bnone	a8, a5, .Lz1	// if byte 1 is zero
	bnone	a8, a6, .Lz2	// if byte 2 is zero
	s32i	a8, a10, 0	// store word to dst
	bany	a8, a7, 1b	// if byte 3 is zero
#endif /* !XCHAL_HAVE_LOOPS */

.Lz3:	/* Byte 3 is zero.  */
	leaf_return

.Lz0:	/* Byte 0 is zero.  */
#ifdef __XTENSA_EB__
	movi	a8, 0
#endif
	s8i	a8, a10, 0
	leaf_return

.Lz1:	/* Byte 1 is zero.  */
#ifdef __XTENSA_EB__
        extui   a8, a8, 16, 16
#endif
	s16i	a8, a10, 0
	leaf_return

.Lz2:	/* Byte 2 is zero.  */
#ifdef __XTENSA_EB__
        extui   a8, a8, 16, 16
#endif
	s16i	a8, a10, 0
	movi	a8, 0
	s8i	a8, a10, 2
	leaf_return

	.align	4
.Ldstunaligned:
#if XCHAL_HAVE_LOOPS
	movi	a8, 0		// set up for the maximum loop count
	loop	a8, 2f		// loop forever (almost anyway)
#endif
1:	l8ui	a8, a3, 0
	addi	a3, a3, 1
	s8i	a8, a10, 0
	addi	a10, a10, 1
#if XCHAL_HAVE_LOOPS
	beqz	a8, 2f
#else
	bnez	a8, 1b
#endif
2:	leaf_return

	.end schedule

	.size	strcpy, . - strcpy
