; Copyright (c) 2021 ozforester. All rights reserved.
; Use of this source code is goverened by a MIT license
; mega8 RC@4MHz ^SUT ( H:D9, L:C3 )
; feeds si5351a with four predefined sets of registers
; version w/o stepping, pcint, timer and code optimization

#include <avr/io.h>
#undef  __SFR_OFFSET
#define __SFR_OFFSET 0
#define butA 138
#define butB 110
#define butC 69
#define butD 23
#define dev 5
#define ADDRESS 0xC0
#define twi_port PORTC
#define twi_pin  PINC
#define twi_ddr  DDRC
#define scl 1 ; PC1
#define sda 0 ; PC0
#define ack 6 ; ack-bit

temp     = 16	; common reg
data     = 17	; twi data reg
register = 18	; osc register number
value	 = 19	; osc register value
rc       = 20	; registers counter
bytec    = 21	; i2c byte shift
state    = 22	; i2c status
twcntr   = 23	; i2c clock delay
dlcntr   = 24   ; time delay
btn      = 25   ; adc sample

.section .data

regs1: ; (1 MHz)
.byte  26, 0xff
.byte  27, 0xff
.byte  28, 0x00
.byte  29, 0x10
.byte  30, 0x00
.byte  31, 0xf0
.byte  32, 0x00
.byte  33, 0x00
.byte  42, 0x00
.byte  43, 0x01
.byte  44, 0x01
.byte  45, 0xc0
.byte  46, 0x00
.byte  47, 0x00
.byte  48, 0x00
.byte  49, 0x00
.byte 177, 0xa0
.byte  16, 0x4f

regs2: ; (1.5 MHz)
.byte  25, 0xff
.byte  27, 0xff
.byte  28, 0x00
.byte  29, 0x10
.byte  30, 0x00
.byte  31, 0xf0
.byte  32, 0x00
.byte  33, 0x00
.byte  42, 0x00
.byte  43, 0x01
.byte  44, 0x01
.byte  45, 0x2a
.byte  46, 0x00
.byte  47, 0x00
.byte  48, 0x00
.byte  49, 0x00
.byte 177, 0xa0
.byte  16, 0x4f

regs3: ; (2 MHz)
.byte  26, 0xff
.byte  27, 0xff
.byte  28, 0x00
.byte  29, 0x10
.byte  30, 0x00
.byte  31, 0xf0
.byte  32, 0x00
.byte  33, 0x00
.byte  42, 0x00
.byte  43, 0x01
.byte  44, 0x00
.byte  45, 0xdf
.byte  46, 0x00
.byte  47, 0x00
.byte  48, 0x00
.byte  49, 0x00
.byte 177, 0xa0
.byte  16, 0x4f

regs4: ; (2.5 MHz)
.byte  26, 0xff
.byte  27, 0xff
.byte  28, 0x00
.byte  29, 0x10
.byte  30, 0x00
.byte  31, 0xf0
.byte  32, 0x00
.byte  33, 0x00
.byte  42, 0x00
.byte  43, 0x01
.byte  44, 0x00
.byte  45, 0xb2
.byte  46, 0x00
.byte  47, 0x00
.byte  48, 0x00
.byte  49, 0x00
.byte 177, 0xa0
.byte  16, 0x4f

.section .text

.global main

main:				;
        rcall delay             ; sut+
	rcall adc_init		; adc
	rcall ba		; 1 MHz
	m1: rcall button	; w/o sleep
	rcall delay		;
	rjmp m1			;
ret				;

.macro between min max
	ser temp
	cpi btn, \max
	brsh bet\@
	cpi btn, \min
	brlo bet\@
	clr temp
	bet\@:
.endm

button: ; mux3 into btn reg
	rcall adc_read
	between butA-20 butA+dev
	tst temp
	breq ba
	between butB-dev butB+dev
        tst temp
	breq bb
	between butC-dev butC+dev
        tst temp
	breq bc
	between butD-dev butD+dev
        tst temp
	breq bd
	rjmp but2 ; skip
	ba: ; A
	ldi ZL, lo8(regs1)
        ldi ZH, hi8(regs1)
	rcall led1
	rjmp but1
        bb: ; B
        ldi ZL, lo8(regs2)
        ldi ZH, hi8(regs2)
        rcall led2
        rjmp but1
        bc: ; C
        ldi ZL, lo8(regs3)
        ldi ZH, hi8(regs3)
        rcall led3
        rjmp but1
        bd: ; D
        ldi ZL, lo8(regs4)
        ldi ZH, hi8(regs4)
        rcall led4
	but1: ; program
	rcall burst ; write
	but2: ; skipped
	rcall delay
ret

adc_read:
	sbi ADCSRA, ADSC	; start conversion
	adc:
	sbis ADCSRA, ADIF	; conversion complete
	rjmp adc		;
	in btn, ADCH		; msb sample
ret

adc_init:
	cbi DDRC, PC3		; PC3 as input
	sbi ADMUX, REFS0	;
	sbi ADMUX, REFS1	; internal reference 2.56
	sbi ADMUX, ADLAR	; 8 bit enough
        sbi ADMUX, MUX1         ;
	sbi ADMUX, MUX0		; C3 mux
	sbi ADCSRA, ADPS2	;
	sbi ADCSRA, ADPS1	; prescaler 62.5 kHz
        sbi ADCSRA, ADEN        ; enable adc
ret

burst:			    	;
        clr rc                  ;
        burst1:                 ;
        lpm register, Z     	; read numb
        adiw Z, 1
        lpm value, Z        	; read value
        rcall write_reg         ;
        inc rc                  ;
	cpi rc, 18		;
	breq burst2		;
        adiw Z, 1		;
	rjmp burst1		; next reg
	burst2:			;
ret				;

write_reg:			;
        rcall i2c_start         ;
        rcall i2c_slaw          ;
	mov data, register	;
        rcall i2c_write         ;
        mov data, value		;
        rcall i2c_write         ;
        rcall i2c_stop          ;
ret				;

.macro pulldown wire
        sbi twi_ddr, \wire ; out
        cbi twi_port, \wire ; low
	nops
.endm

.macro release wire
        cbi twi_ddr, \wire ; input
        cbi twi_port, \wire ; w/o pull-up
	nops
.endm

.macro latch ; released clock pulse
        release scl ; release
        waitrlz scl ; delayed till stable high
	nops
        pulldown scl ; pull down
	nops
.endm

.macro waitrlz wire
	wf\@: ; multiple placements
        sbis twi_pin, \wire ; wait till high
        rjmp wf\@ ; sinked
	nops
.endm

.macro nops ; 25 us
        ldi twcntr, 10
	nops\@: dec twcntr
	brne nops\@
.endm

delay: ; ~ 16 ms
	ldi dlcntr, 255
	dl1:
	push dlcntr
       	ldi dlcntr, 255
	dl2:
	dec dlcntr
	brne dl2
	pop dlcntr
	dec dlcntr
	brne dl1
ret

i2c_start: ; start condition
        waitrlz scl ; released
        pulldown sda ; data low while scl is high
	nops
        pulldown scl ; clk low
ret

i2c_stop: ; stop condition
        release scl ; release clk
        waitrlz scl ; wait till it high
        release sda ; release data
ret

i2c_slaw:
	ldi data, ADDRESS
	rcall i2c_write
ret

i2c_write: ; write one byte (<data)
        cbr state, 1<<ack ; clear ack bit
        ldi bytec, 0x08 ; byte
	twn: sbrs data, 7 ; msb state
        rjmp msb_low ; not set
        release sda ; set
        rjmp tws
	msb_low: pulldown sda
	tws: latch ; clock
        lsl data ; shift next to msb
        dec bytec ; till Z
        brne twn ; send next
        release sda ; whole byte sent
        release scl ; release wires
        sbis twi_port, sda ; latch ack slot
        sbr state, 1<<ack ; ok latched by slave
        waitrlz scl ; stable
        pulldown scl ; done
ret

led1:
        cbi DDRB, PB1
        cbi DDRB, PB2
        sbi DDRD, PD7
        sbi PORTD, PD7
        sbi DDRB, PB0
        cbi PORTB, PB0
ret

led2:
        cbi DDRB, PB1
        cbi DDRB, PB2
        sbi DDRD, PD7
        cbi PORTD, PD7
        sbi DDRB, PB0
        sbi PORTB, PB0
ret

led3:
        cbi DDRD, PD7
        cbi DDRB, PB0
        sbi DDRB, PB1
        sbi PORTB, PB1
        sbi DDRB, PB2
        cbi PORTB, PB2
ret

led4:
        cbi DDRD, PD7
        cbi DDRB, PB0
        sbi DDRB, PB1
        cbi PORTB, PB1
        sbi DDRB, PB2
        sbi PORTB, PB2
ret

.end
