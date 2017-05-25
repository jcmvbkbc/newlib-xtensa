// crt1-sim.S
// For the Xtensa simulator target, this code sets up the C calling context
// and calls main()  (via __clibrary_start).
// Control arrives here at _start from the reset vector or from crt0-app.S.

// Copyright (c) 1998-2016 Tensilica Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#include <xtensa/config/core-isa.h>
#include "simcall.h"


// Exports
.global _start

// Imports
//   __clibrary_init	from C library (eg. newlib or uclibc)
//   exit		from C library
//   main		from user application
//   __stack		from linker script (see LSP Ref Manual)

.type	__clibrary_init, @function
.type	main, @function
.type	exit, @function

#define SYS_iss_argc 1000
#define SYS_iss_argv_size 1001
#define SYS_iss_set_argv 1002

#define PS_UM	0x20

// Macros to abstract away ABI differences

#if __XTENSA_CALL0_ABI__
# define CALL	call0
# define CALLX	callx0
# define ARG1	a2	/* 1st outgoing call argument */
# define ARG2	a3	/* 2nd outgoing call argument */
# define ARG3	a4	/* 3rd outgoing call argument */
# define ARG4	a5	/* 4th outgoing call argument */
# define ARG5	a6	/* 5th outgoing call argument */
# define PS_WOE_ABI 0
#elif XCHAL_HAVE_XEA3
# define CALL	call8
# define CALLX	callx8
# define ARG1	a10	/* 1st outgoing call argument */
# define ARG2	a11	/* 2nd outgoing call argument */
# define ARG3	a12	/* 3rd outgoing call argument */
# define ARG4	a13	/* 4th outgoing call argument */
# define ARG5	a14	/* 5th outgoing call argument */
#else
# define CALL	call4
# define CALLX	callx4
# define ARG1	a6	/* 1st outgoing call argument */
# define ARG2	a7	/* 2nd outgoing call argument */
# define ARG3	a8	/* 3rd outgoing call argument */
# define ARG4	a9	/* 4th outgoing call argument */
# define ARG5	a10	/* 5th outgoing call argument */
# define PS_WOE_ABI 0x40000
#endif

		.data
		.weak	_start_envp	// allow overriding
		.align	4
_start_envp:	.word	0		// empty environ



	.text
	.align 4
	.literal_position

_start:
	//  _start is typically NOT at the beginning of the text segment --
	//  it is always called from either the reset vector or other code
	//  that does equivalent initialization (such as crt0-app.S).
	//
	//  Assumptions on entry to _start:
	//	- (XEA1/XEA2) low (level-one) and medium priority interrupts are
	//	  disabled via PS.INTLEVEL and/or INTENABLE (PS.INTLEVEL is expected
	//	  to be zeroed, to potentially enable them, before calling main)
	//	- (XEA3) all interrupts are disabled  via PS.DI. PS.DI will be cleared
	//	  before calling main.
	//	- C calling context not initialized:
	//	  - PS not initialized
	//	  - SP not initialized
	//	- the following are initialized:
	//	  - LITBASE, cache attributes, WindowBase, WindowStart,
	//	    CPENABLE, FP's FCR and FSR, EXCSAVE[n]

	// Keep a0 zero.  It is used to initialize a few things.
	// It is also the return address, where zero indicates
	// that the frame used by _start is the bottommost frame.
	//
	movi	a0, 0		// keep this register zero.


	// Initialize the stack pointer.
	// See the "ABI and Software Conventions" chapter in the
	// Xtensa ISA Reference manual for details.

	// NOTE: Because the _start routine does not use any memory in its
	// stack frame, and because all of its CALL instructions use a
	// window size of 4, the stack frame for _start can be empty.
	movi	sp, __stack

	// reserve stack space for
	//    - argv array
	//    - argument strings
	movi	a2, SYS_iss_argv_size
	simcall		// returns size of argv[] + its strings in a2
	// Keep stack 16-byte aligned.
	addi	a2, a2, 15
	srli	a2, a2, 4
	slli	a2, a2, 4
	// No need to use MOVSP because we have no caller (we're the
	// base caller); in fact it's better not to use MOVSP in this
	// context, to avoid unnecessary ALLOCA exceptions and copying
	// from undefined memory:
	sub	sp, sp, a2

	/*
	 *  Now that sp (a1) is set, we can set PS as per the application
	 *  (user vector mode, enable interrupts, enable window exceptions if applicable).
	 */
#if XCHAL_HAVE_EXCEPTIONS
# if XCHAL_HAVE_XEA3
	movi	a3, PS_STACK_FIRSTINT	// PS.STK = FirstInt, PS.DI = 0
	wsr.ps	a3
# else
	movi	a3, PS_UM|PS_WOE_ABI	// PS.WOE = 0|1, PS.UM = 1, PS.EXCM = 0, PS.INTLEVEL = 0
	wsr.ps	a3
# endif
	rsync
#endif


	/*
	 *  Do any initialization that affects the memory map, such as
	 *  setting up TLB entries, that needs to be done before we can
	 *  successfully clear BSS (e.g. if some BSS segments are in
	 *  remapped areas).
	 *
	 *  NOTE:  This hook works where the reset vector does not unpack
	 *  segments (see "ROM packing" in the LSP manual), or where
	 *  unpacking of segments is not affected by memory remapping.
	 *  If ROM unpacking is affected, TLB setup must be done in
	 *  assembler from the reset vector.
	 *
	 *  The __memmap_init() routine can be a C function, however it
	 *  does not have BSS initialized!  In particular, __memmap_init()
	 *  cannot set BSS variables, i.e. uninitialized global variables
	 *  (they'll be wiped out by the following BSS clear), nor can it
	 *  assume they are yet initialized to zero.
	 *
	 *  The __memmap_init() function is optional.  It is marked as a
	 *  weak symbol, so that it gets valued zero if not defined.
	 */
	.weak	__memmap_init
	movi	a4, __memmap_init
	beqz	a4, 1f
	CALLX	a4
1:


	/*
	 *  Clear the BSS (uninitialized data) segments.
	 */
        movi    a6, _bss_start
        movi    a7, _bss_end
        bgeu    a6, a7, 2f
1:      s32i    a0, a6, 0
        addi    a6, a6, 4
        bltu    a6, a7, 1b
2:

	/*
	 *  Call __clibrary_init to initialize the C library:
	 *
	 *  void __clibrary_init(int argc, char ** argv, char ** environ,
	 *		void(*init_func)(void), void(*fini_func)(void));
	 */

	// Get argv with the arguments from the ISS
	mov	a3, sp		// tell simcall where to write argv[]
	movi	a2, SYS_iss_set_argv
	simcall			// write argv[] array at a3

	movi	a2, SYS_iss_argc
	simcall			// put argc in a2

#if __XTENSA_CALL0_ABI__
	mov 	a12, a2			// save argc (a2 is ARG1)
#else
	mov 	ARG1, a2		// argc
#endif
	mov	ARG2, sp		// argv
	movi 	ARG3, _start_envp	// envp
	movi 	ARG4, _init		// _init
	movi	ARG5, _fini		// _fini
	CALL	__clibrary_init

	//  Call:   int main(int argc, char ** argv, char ** environ);
#if __XTENSA_CALL0_ABI__
	mov 	ARG1, a12		// argc
#else
	mov	ARG1, a2		// argc
#endif
	mov	ARG2, sp		// argv
	movi	ARG3, _start_envp	// envp = [0]
	CALL	main
	//  The return value is the same register as the first outgoing argument.
	CALL	exit			// exit with main's return value
	// Does not return here.

	.size	_start, . - _start
