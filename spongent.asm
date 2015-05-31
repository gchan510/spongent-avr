/*
 * spongent.asm
 *
 *  Created: 20-2-2014 16:01:24
 *   Author: Wouter de Groot and Erik Schneider
 */

 /*
 Need to r/w:
	state_in	RAM		permute		Y
	state_out	RAM		permute		X
	input		FLASH	absorb		Z
	output		RAM		squeeze		X
	sbox		FLASH	permute		Z
 */

 .def ZERO = r1
 .def WHICHBUF = r2
 .def TEMP2 = r3
 .def LFSR = r16
 .def RLFSR = r17
 .def CBYTE = r18
 .def BITCTR = r19
 .def PJAY = r20
 .def OFFSET = r21
 .def INPUTCTR = r22
 .def OUTPUTCTR = r23
 .def CHANGER = r24
 .def TEMP1 = r25


 .equ HASH_SIZE = $10		; For spongent128/128/8 the output is $10 bytes
 .equ STATE_SIZE = $88		; Internal state is hash+rate*8 bits
 .equ INPUT_SIZE = $9		; For this assignment the input is hardcoded
 .equ LFSR_INIT = $7d		; Precursor of $7a; we run the step first so first iteration uses $7a.

.dseg
.org $60
	state1:		.byte STATE_SIZE/8
.org $80
	state2:		.byte STATE_SIZE/8
.org $a0
	output:		.byte HASH_SIZE

.cseg
.org $0200
	sbox:
	.db $ed, $b0, $21, $4f, $7a, $85, $9c, $36
.org $0300
	input:
	.db $53, $70, $6f, $6e, $67, $65, $6e, $74, $80, $00	; "Spongent" + padding + alignment

.org $0
; EXECUTION STARTS HERE
init:
	ldi CHANGER, $e0			; This switches between $60 and $80 (cannot EOR with immediate)
	ldi YL, state1				; Contract: YL always points to the fresh read/writable state
	mov WHICHBUF, YL
	ldi OUTPUTCTR, HASH_SIZE	; Keep a counter of hash output bytes processed
	ldi INPUTCTR, INPUT_SIZE	; Keep a counter of input bytes processed

absorb:
	ldi ZH, high(2*input)
	ldi ZL, low(2*input+INPUT_SIZE)	; Point to the end of input
	sub ZL, INPUTCTR			; Subtract counter. We now go through bytes incrementally
	lpm TEMP1, Z
	ldd TEMP2, Y+STATE_SIZE/8-1
	eor TEMP2, TEMP1
	std Y+STATE_SIZE/8-1, TEMP2
	rcall permute
	dec INPUTCTR
	brne absorb

squeeze:
	ldi XL, output+HASH_SIZE	; Point to the end of output
	sub XL, OUTPUTCTR			; Subtract reverse counter. We now go through bytes incrementally
	ldd TEMP1, Y+HASH_SIZE
	st X, TEMP1
	rcall permute				; This runs once too many, but it makes the jumping logic smaller.
	dec OUTPUTCTR
	brne squeeze

done:
	rjmp done					; Park the uC here. Hash output starts at RAM $a0

/*
* A full permutation function is performed here. All 70 rounds on all state bits.
* Note that this function either reads from state1 and writes to state2 or swaps the buffers.
* This is an unfortunate RAM increase, but the pLayer forces us to write to new memory,
* or we'd overwrite bits we hadn't read yet.
*/
permute:
	ldi ZH, high(2*sbox)		; Some setup first
	ldi ZL, low(2*sbox)
	ldi LFSR, LFSR_INIT

permute_round:

lfsr_step:
	lsl	LFSR					;MSB is always zero
	rol LFSR					;Now we can examine whether N ^ C is set (i.e. whether V is)
	brvc lfsr_step_zero
	sbr LFSR, 2					;still rotated, so bit 0 is in place 1.
lfsr_step_zero:
	lsr LFSR					;Step complete, we undo the extra shift left (and don't care about MSB)
	ldi RLFSR, $80				;signal bit, when ror puts it into C we know we're done.
	push LFSR					;we rotate r16 into r17 so we want to be able to get the value back
lfsr_step_rotate:
	rol LFSR
	ror RLFSR
	brcc lfsr_step_rotate
	pop LFSR

	eor WHICHBUF, CHANGER		; each round goes through entire state, so we must change buffers
	ldi PJAY, $0				; and so also reset bit iterator

	ldd CBYTE, Y+STATE_SIZE/8-1	; First we add LFSR values. We use the 'old' value and update after
	eor CBYTE, LFSR
	std Y+STATE_SIZE/8-1, CBYTE

	ld CBYTE, Y
	eor CBYTE, RLFSR
	st Y, CBYTE

process_byte:					; Go through both sbox and pLayer for every byte
	ld CBYTE, Y
	st Y+, ZERO					; Guarantee this byte is ready for reading in next round
	rcall sBoxByte				; Use Kostas' subroutine to substitute CBYTE
	ldi BITCTR, $7				; pLayer needs to run on all 8 bits of CBYTE

pLayer:
	; first find target position
	mov OFFSET, PJAY
	cbr OFFSET, $f8				; lowest 3 bits are the offset within target byte
	mov XL, PJAY
	lsr XL						; top 5 bits represent the target byte
	lsr XL
	lsr XL
	add XL, WHICHBUF

	mov TEMP2, ZERO
	lsl CBYTE					; put target bit in C
pLayer_position_bit:
	ror TEMP2					; Get target bit into tmp from C
	dec OFFSET
	brge pLayer_position_bit	; branch so long as OFFSET hasn't overflown (i.e. when MSB=N=0)
	ld TEMP1, X					; on ATMega, these 3 could be LAS Z, TEMP2
	or TEMP1, TEMP2
	st X, TEMP1

	cpi PJAY, STATE_SIZE-1		; If it's precisely state-1 then we've just processed the last bit
	breq pLayer_complete

	; iterative modulus. Since j+=1, simply add b/4.
	;Since PJAY can never grow larger than b+b/4 simply subtracting b is sufficient as modulus operation
	subi PJAY, -STATE_SIZE/4	; b/4 is 136/4 is $22. No add with immediate, so sub with negative value
	cpi PJAY, STATE_SIZE		; Test b instead of b-1, this way 135 stays 135 for final bit. Actual sub is unchanged
	brmi pLayer_no_mod
	subi PJAY, STATE_SIZE-1
pLayer_no_mod:
	dec BITCTR
	brge pLayer					; Not all bits have been done.
	rjmp process_byte			; All bits processed. Move on to new byte.

pLayer_complete:
	mov YL, WHICHBUF

	cpi LFSR, $3f				; The 7 LFSR bits are all 1, 70 rounds have passed, time to quit.
	brne permute_round
	ret							; Permute complete

	; This subroutine is lifted from Kostas' presentation on PRESENT.
	; Two dead/useless instructions were removed.
	; Please consult our documentation to see us explain it in our own words.
sBoxByte:
	rcall sBoxLowNibbleAndSwap	; apply s-box to low nibble and swap nibbles
								; after return, do it again.
sBoxLowNibbleAndSwap:
	mov ZL, CBYTE
	cbr ZL, $f0
	asr ZL
	lpm TEMP1, Z
	brcs odd_unpack
even_unpack:
	swap TEMP1
odd_unpack:
	cbr TEMP1, $f0
	cbr CBYTE, $f
	or CBYTE, TEMP1
	swap CBYTE
	ret
