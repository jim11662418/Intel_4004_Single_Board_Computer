               PAGE 0                  ; suppress page headings in ASW listing file
               cpu 4004                ; tell the Macro Assembler AS that this source is for the Intel 4004.
            
;--------------------------------------------------------------------------------------------------
; Test of an alternate serial port using  the least significant bit of 4265 GPIO port Z (pin 14) 
; to transmit and the least significant bit of 4265 GPIO port Y (pin 19) to receive.
;
; Requires the use of a terminal emulator connected to the SBC
; set for 9600 bps, no parity, 8 data bits, 1 stop bit.
;
; Syntax is for the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;----------------------------------------------------------------------------------------------------

               include "reg4004.inc"   ; Include 4004 register definitions.
               include "bitfuncs.inc"  ; Include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).            

; I/O port addresses...
GPIO           equ 80H                 ; address of the 4265 General Purpose I/O device

GPIOMODE7      equ 0111B               ; port W, X and Y as inputs, port Z as output

               org 0000H               ; beginning of EPROM
;--------------------------------------------------------------------------------------------------
; Power-on-reset Entry
;--------------------------------------------------------------------------------------------------
reset:         nop                     ; To avoid problems with power-on reset, the first instruction at
                                       ; program address 0000 should always be an NOP (don't know why).
            
               fim P0,GPIO             ; address of the 4265 GPIO device
               src P0
               ldm GPIOMODE7           
               wmp                     ; program ports W, X and Y as inputs; port Z as output
               ldm 1
               wr3                     ; set alternate serial output (pin 14 of 4265) high to indicate 'MARK'
               
               jms banner
            
loop           jms getchar2            ; get a character from the alternate serial port
               jms putchar2            ; transmit the character using the alternate serial port
               jun loop

;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 alternate serial input function 'getchar2'
; receives serial input on least significant bit of port Y on the 4265 (pin 19).
; returns the 8 bit received character in P1 (R2,R3). also uses P7 (R14,R15).
;--------------------------------------------------------------------------------------------------                
getchar2:      fim P7,GPIO
               src P7                  ; set 4265 GPIO port address   
               ldm 0
               xch R3                  ; clear least significant bits
               ldm 0
               xch R2                  ; clear most significant bits
               ldm 16-4                ; 4 bits
               xch R14                 ; R14 is the counter for bits 0-3
               ldm 16-4                ; 4 bits
               xch R15                 ; R15 is the counter for bits 4-7
                
; wait for the start bit (10 cycles)             
getchar2a:     rd2                     ; read port Y 
               nop
               ;wr3                    ; echo the bit to port Z
               rar                     ; rotate least significant bit of port Y into carry
               jcn c,getchar2a         ; loop back until input is low (start bit)
               nop
               nop
               nop
               nop
               nop
                
; receive least significant bits 0-3. each bit takes 10 cycles                
getchar2b:     rd2                     ; read port Y
               nop
               ;wr3                    ; echo the received bit to port Z
               rar                     ; rotate the received bit into carry
               ld R3                   ; recall the previously received bits from R3
               rar                     ; rotate carry into high order bit of the accumulator
               xch R3                  ; save the received bits in R3
               nop
               nop
               isz R14,getchar2b

; receive most significant bits 4-7. each bit takes 9 cycles               
getchar2c:     rd2                     ; read port Y
               nop
               ;wr3                    ; echo the received bit to port Z
               rar                     ; rotate the received bit into carry
               ld R2                   ; recall the previously received bits from R2
               rar                     ; rotate carry into high order bit of the accumulator
               xch R2                  ; save the received bits in R2
               nop
               isz R15,getchar2c

; receive the stop bit
               rd2                     ; read port Y
               nop
               ;wr3                    ; echo the received bit to port Z
               rar                     ; rotate least significant bit of port Y into carry                
               jcn c,getchar2d         ; jump if 1 (stopbit detected)
               bbl 1                   ; else return 1 to indicate stop bit was 0 (timing error)
getchar2d:     bbl 0                   ; return 0 to indicate correct timing                            

;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 alternate serial output function 'putchar2'
; send the character in P1 (R2,R3) to the least significant bit of port Z on the 4265 (pin 14)
; in addition to P1 (R2,R3) also uses P7 (R14,R15). preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar2:      fim P7,GPIO
               src P7                  ; set port address
               ldm 16-5
               xch R14                 ; counter for 5 bits (start bit plus bits 0-3)
               ld R3                   ; load the least significant bits from R3
               clc                     ; clear carry to make the start bit
               ral
            
; send 5 bits; the start bit and least significant bits 0-3. each bit takes 9 cycles
putchar2a:     nop
               nop
               nop
               nop
               nop
               wr3                     ; output the bit to port Z
               rar                     ; rotate the next bit into position
               isz R14, putchar2a

               ldm 16-5                ; 5 bits (bits 4-7 plus stop bit)
               xch R14
               ld R2                   ; load the most significant bits from R2
               stc                     ; this will become the stop bit
               nop
               nop
            
; send 5 bits; most significant bits bits 4-7 and the stop bit. each bit takes 10 cycles
putchar2b:     wr3                     ; output the bit to port Z
               nop
               nop
               nop
               nop
               nop
               nop
               rar                     ; rotate the next bit into position
               isz R14, putchar2b
               bbl 0      
               
;-----------------------------------------------------------------------------------------
; This function is used by all the text string printing functions. If the character in P1 
; is zero indicating the end of the string, returns 0. Otherwise prints the character and 
; increments P0 to point to the next character in the string then returns 1.
;-----------------------------------------------------------------------------------------
txtout:        ld R2                   ; load the most significant nibble into the accumulator
               jcn nz,txtout1          ; jump if not zero (not end of string)
               ld  R3                  ; load the least significant nibble into the accumulator
               jcn nz,txtout1          ; jump if not zero (not end of string)
               bbl 0                   ; end of text found, branch back with accumulator = 0

txtout1:       jms putchar2            ; print the character in P1 to the alternate serial port
               inc R1                  ; increment least significant nibble of pointer
               ld R1                   ; get the least significant nibble of the pointer into the accumulator
               jcn zn,txtout2          ; jump if zero (no overflow from the increment)
               inc R0                  ; else, increment most significant nibble of the pointer
txtout2:       bbl 1                   ; not end of text, branch back with accumulator = 1            

               org 0100H
; this function and the text to be printed must all be on the same page.            
banner:        fim P0,lo(bannertxt)
               fin P1                  ; fetch the character pointed to by P0 into P1
               jms txtout              ; print the character, increment the pointer to the next character
               jcn zn,$-3              ; go back for the next character
               bbl 0

bannertxt:     data "\r\nIntel 4004 SBC alternate serial port test\r\n"
               data "Assembled on ",DATE," at ",TIME,"\r\n\n",0

               end
            
