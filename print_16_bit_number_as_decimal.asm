                PAGE 0                          ; suppress page headings in ASW listing file
                cpu 4004

;=================================================================================================
; prints the 16 bit contents of P2P3 (R4,R5,R6,R7) as a 5 digit decimal number.
; Assemble with the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;=================================================================================================

;---------------------------------------------------------------------------------------------------------------------------------
; Copyright 2024 Jim Loos
;
; Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
; (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
; publish, distribute, sub-license, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
; so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
; IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;---------------------------------------------------------------------------------------------------------------------------------

; Conditional jumps syntax for Macro Assembler AS:
; jcn t     jump if test = 0 - positive voltage or +5VDC
; jcn tn    jump if test = 1 - negative voltage or -10VDC
; jcn c     jump if cy = 1
; jcn cn    jump if cy = 0
; jcn z     jump if accumulator = 0
; jcn zn    jump if accumulator != 0

            include "bitfuncs.inc"     ; include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).
            include "reg4004.inc"      ; include 4004 register definitions.

CR              equ 0DH
LF              equ 0AH

; I/O port address
SERIALPORT      equ 00H

reset:          nop                     ; "To avoid problems with power-on reset, the first instruction at
                                        ; program address 0000 should always be an NOP." (don't know why)
                ldm 0001B
                fim P0,SERIALPORT
                src P0
                wmp                     ; set serial output port high to indicate MARK
                jms newline
         
                fim P4,0FFH
                fim P5,0FFH
incloop:        inc R11                 ; increment the contents of P4P5 (R8,R9,R10,R11)
                ld R11
                jcn nz,testprn
                inc R10
                ld R10
                jcn nz,testprn
                inc R9
                ld R9
                jcn nz,testprn
                inc R8

testprn:        ld R8                   ; copy the contents of P4P5 (R8,R9,R10,R11) to P2P3 (R4,R5,R6,R7)
                xch R4
                ld R9
                xch R5
                ld R10
                xch R6
                ld R11
                xch R7
                jms prnDecimal          ; print the contents of P2P3 as a decimal number
                jms newLine
                jun incloop

;-----------------------------------------------------------------------------------------
; prints the 16 bit contents of P2P3 (R4,R5,R6,R7) as a decimal number.
; leading zeros are suppressed.
; in addition to P2 and P3 uses P0,P1,P6 and P7.
;-----------------------------------------------------------------------------------------
prnDecimal:     ldm 0
                xch R1                  ; clear the leading zero flag (zero means do not print '0')
                
; ten thousands digit
; count the number of times 10,000 can be subtracted from the number in P2P3 before causing an underflow              
                ldm 0
                xch R0                  ; clear the digit counter
                fim P6,10000 >> 8       ; high byte of 10000
                fim P7,10000 & 0FFH     ; low byte of 10000
prnDecimal1:    jms sub16               ; subtract 10000 from the number in P2P3
                inc R0                  ; increment the ten thousands digit counter 
                jcn z,prnDecimal1       ; jump if no underflow
                jms add16               ; the previous subtraction caused an underflow, add 10000 back to P2P3
                ld R0
                dac                     ; decrement the ten thousands digit counter because of the previous underflow
                jcn z,prnDecimal2       ; do not print the ten thousands digit if it is is zero
                xch R3                  ; else, move the ten thousands digit to P1 and convert to ASCII
                ldm 3
                xch R2                 
                jms putchar             ; print the ten thousands digitt
                ldm 1
                xch R1                  ; set the leading zero flag (print all zeros from now on)

; thousands digit
; count the number of times 1000 can be subtracted from the number in P2P3 before causing an underflow   
prnDecimal2:    ldm 0
                xch R0                  ; clear the digit counter
                fim P6,1000 >> 8        ; high byte of 1000
                fim P7,1000 & 0FFH      ; low byte of 1000
prnDecimal2a:   jms sub16               ; subtract 1000 from the number in P2P3
                inc R0                  ; increment the thousands digit counter 
                jcn z,prnDecimal2a      ; jump if no underflow
                jms add16               ; the previous subtraction caused an underflow, add 1000 back to P2P3
                ld R0
                dac                     ; decrement the thousands digit counter because of the previous underflow
                xch R3                  ; else, move the thousands digit to P1 and convert to ASCII
                ldm 3
                xch R2   
                ld R3
                jcn nz,prnDecimal2b     ; print the thousands digit if it is not zero
                ld R1
                jcn z,prnDecimal3       ; else, skip the thousands digit if the leading zero flag is 0
prnDecimal2b:   jms putchar             ; print the thoudands digitt
                ldm 1
                xch R1                  ; set the leading zero flag (print all zeros from now on)                

; hundreds digit...  
; count the number of times 100 can be subtracted from the number in P2P3 before causing an underflow          
prnDecimal3:    ldm 0
                xch R0                  ; clear the digit counter
                fim P6,100 >> 8         ; high byte of 100
                fim P7,100 & 0FFH       ; low byte of 100
prnDecimal3a:   jms sub16               ; subtract 100 from the number in P2P3
                inc R0                  ; increment the hundreds digit counter 
                jcn z,prnDecimal3a      ; jump if no underflow
                jms add16               ; the previous subtraction caused an underflow, add 100 back to P2P3
                ld R0
                dac                     ; decrement the hundreds digit counter because of the previous underflow
                xch R3                  ; else, move the hundreds digit to P1 and convert to ASCII
                ldm 3
                xch R2 
                ld R3
                jcn nz,prnDecimal3b     ; print the hundreds digit if it is not zero
                ld R1
                jcn z,prnDecimal4       ; else, skip the hundreds digit if the leading zero flag is 0
prnDecimal3b:   jms putchar             ; print the hundreds digit
                ldm 1
                xch R1                  ; set the leading zero flag (print all zeros from now on)
                
; tens digit...   
; count the number of times 10 can be subtracted from the number in P2P3 before causing an underflow                        
prnDecimal4:    ldm 0
                xch R0                  ; clear the digit counter
                fim P6,10 >> 8          ; high byte of 10
                fim P7,10 & 0FFH        ; low byte of 10
prnDecimal4a:   jms sub16               ; subtract 10 from the number in P2P3
                inc R0                  ; increment the tens digit counter 
                jcn z,prnDecimal4a      ; jump if no underflow
                jms add16               ; the previous subtraction caused an underflow, add 10 back to P2P3
                ld R0
                dac                     ; decrement the tens digit counter because of the previous underflow
                xch R3                  ; else, move the tens digit to P1 and convert to ASCII
                ldm 3
                xch R2 
                ld R3
                jcn nz,prnDecimal4b     ; print the hundreds digit if it is not zero
                ld R1
                jcn z,prnDecimal5       ; else, skip the hundreds digit if the leading zero flag is 0
prnDecimal4b:   jms putchar             ; print the hundreds digit
                
; units digit...   
; whatever remains in P2P3 at this point represents the units digit            
prnDecimal5:    ld R7                   ; move what remains in P2P3 to P1 and convert to ASCII
                xch R3
                ldm 3
                xch R2
                jun putchar             ; print the units digit
                
;--------------------------------------------------------------------------------------------------
; Subtract the 16 bit contents of P6P7 (R12,R13,R14,R15) from the 16 bit contents of P2P3 (R4,R5,R6,R7).
; The 16 bit difference is returned in P2P3. The contents of P6P7 remain unchanged. 
; Returns 1 if underflow (the difference in P2P3 is negative).
;--------------------------------------------------------------------------------------------------
sub16:          ld R7
                clc   
                sub R15
                xch R7
                
                ld R6
                cmc
                sub R14
                xch R6
                
                ld R5
                cmc
                sub R13
                xch R5
                
                ld R4
                cmc
                sub R12
                xch R4
                
                jcn c,$+3
                bbl 1
                bbl 0       
                
;--------------------------------------------------------------------------------------------------
; Add the 16 bit contents of P6P7 (R12,R13,R14,R15) to the 16 bit contents of P2P3 (R4,R5,R6,R7).
; The 16 bit sum is returned in P2P3. The contents of P6P7 remain unchanged. 
; Returns 1 if overflow (the sum in P2P3 is greater than 65535).
;--------------------------------------------------------------------------------------------------
add16:          clc
                ld R7
                add R15
                xch R7

                ld R6
                add R14
                xch R6
                
                ld R5
                add R13
                xch R5
                
                ld R4
                add R12
                xch R4
                
                jcn nc,$+3
                bbl 1
                bbl 0                
                
                org 0100H
;-----------------------------------------------------------------------------------------
; position the cursor to the start of the next line
; uses P1 and P7
;-----------------------------------------------------------------------------------------
newline:        fim P1,CR
                jms putchar
                fim P1,LF
                jun putchar

;--------------------------------------------------------------------------------------------------
; send the character in P1 to the console serial port (the least significant bit of port 0)
; in addition to P1 (R2,R3) also uses P7 (R14,R15)
; preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar:        fim P7,SERIALPORT
                src P7              ; set port address
                ldm 16-5
                xch R14             ; 5 bits (start bit plus bits 0-3)
                ld R3
                clc                 ; clear carry to make the start bit 0
                ral

; send 5 bits; the start bit and bits 0-3. each bit takes 9 cycles
putchar1:       nop
                nop
                nop
                nop
                nop
                wmp
                rar
                isz R14, putchar1

                ldm 16-5            ;(1) 5 bits (bits 4-8 plus stop bit)
                xch R14
                ld R2
                stc
                nop
                nop

; send 5 bits; bits 4-8 and the stop bit. each bit takes 10 cycles
putchar2:       wmp
                nop
                nop
                nop
                nop
                nop
                nop
                rar
                isz R14, putchar2
                bbl 0

                end