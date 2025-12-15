                PAGE 0                          ; suppress page headings in ASW listing file
                cpu 4004

;---------------------------------------------------------------------------------------------------------------------------------
; Copyright 2020 Jim Loos
; 
; Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
; (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
; publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
; so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
; IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;---------------------------------------------------------------------------------------------------------------------------------    

;--------------------------------------------------------------------------------------------------
; RAM firmware test for the Intel 4004 Single Board Computer.
;   used for testing 4002 RAM chips bought from eBay.
;   writes and then reads values 0-15 to all 64 data RAM locations and all 16 status 
;   character locations on a 4002 RAM chip. As written, it tests the first 4002 RAM chip
;   at addresses 00H-3FH. To test different chip, change the “RAMSTART” value.
;
;   prints the hex address of each RAM character tested.
;   flashes LED0 each time the test is completed.
;   turns on LED3 if an error is detected.
;   prints the RAM address where the error is detected.
;
; Requires the use of a terminal emulator connected to the SBC
; set for 9600 bps, no parity, 8 data bits, 1 stop bit.
;
; Assemble with the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;----------------------------------------------------------------------------------------------------

; Conditional jumps syntax for Macro Assembler AS:
; jcn t     jump if test = 0 - positive voltage or +5VDC
; jcn tn    jump if test = 1 - negative voltage or -10VDC
; jcn c     jump if cy = 1
; jcn cn    jump if cy = 0
; jcn z     jump if accumulator = 0
; jcn zn    jump if accumulator != 0

            include "bitfuncs.inc"  ; Include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).
            include "reg4004.inc"   ; Include 4004 register definitions.

CR          equ 0DH
LF          equ 0AH

; I/O port addresses...
SERIALPORT  equ 00H                 ; Address of the serial port. The least significant bit of port 00 is used for serial output.
LEDPORT     equ 40H                 ; Address of the port used to control the red LEDs. "1" turns the LEDs on.

; RAM addresses...
CHIP0       equ 00H                 ; 4002 data RAM chip 0
CHIP1       equ 40H                 ; 4002 data RAM chip 1

RAMSTART    equ CHIP0
RAMEND      equ RAMSTART+40H

            org 0000H               ; beginning of EPROM
;--------------------------------------------------------------------------------------------------
; Power-on-reset Entry
;--------------------------------------------------------------------------------------------------
reset:      nop                     ; "To avoid problems with power-on reset, the first instruction at
                                    ; program address 0000 should always be an NOP." (don't know why)
            ldm 0001B
            fim P0,SERIALPORT
            src P0
            wmp                     ; set RAM serial output port high to indicate MARK

            ldm 0000B            
            fim P0,LEDPORT
            src P0
            wmp                     ; write data to RAM LED output port, set all 4 outputs low to turn off all four LEDs

            fim P6,079H             ; 250 milliseconds delay for serial port
            fim P7,06DH
reset1:     isz R12,reset1
            isz R13,reset1
            isz R14,reset1
            isz R15,reset1

            fim P0,lo(msg0)         ; "Testing data RAM "
txt0:       fin P1                  ; fetch the character pointed to by P0 into P1
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,txt0             ; not yet at the end of the string, go back for the next character
            
            fim P0,RAMSTART
            jms print2hex           ; print RAM start address
            fim P1,'H'
            jms putchar
            fim P1,'-'
            jms putchar
            fim P0,RAMEND
            ld R0
            dac
            xch R0
            ld R1
            dac
            xch R1
            jms print2hex           ; print RAM end address
            fim P1,'H'
            jms putchar
            jms newline

;-------------------------------------------------------------------------
; P3 (R6,R7) holds the RAM address
; P4 (R8,R9) holds the end of RAM address
; R10 holds the value to be written to RAM
; R11 holds the value for the flashing LED
;-------------------------------------------------------------------------
            ldm 0
            xch R11                 ; value for the flashing LED
            
ramtest:    fim P3,RAMSTART
            fim P4,RAMEND
            ldm 0                   ; start with read-write value 0    
            xch R10
            
; RAM data characters 0-F   
loop:       fim P0,lo(msg1)         ; print "Testing"
txt1:       fin P1                  ; fetch the character pointed to by P0 into P1
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,txt1             ; not yet at the end of the string, go back for the next character            
            
            ld R6                   ; R6 holds the RAM register number
            xch R0
            ld R7                   ; R7 holds the RAM character number
            xch R1
            jms print2hex           ; print RAM register number and character number as two hex digits
            fim P1,'H'
            jms putchar
            jms newline

            fim P0,LEDPORT
            src P0
            ld R11
            rar                     ; least significant bit into carry
            cmc                     ; complement it
            ral                     ; back into least significant bit
            wmp                     ; toggle the LED connected to bit zero output of RAM chip 1
            xch R11
         
loop2:      src P3                  ; P3 contains the RAM address 
loop3:      ld R10                  ; retrieve the nibble to be written to RAM from R0
            wrm                     ; write the nibble to data RAM
            rdm                     ; read the nibble from data RAM
            clc
            sub R10                 ; compare by subtraction the nibble read from RAM to the nibble written to RAM
            jcn z,loop4             ; jump if the values match
            jun ramerr              ; else, jump to the error routine
loop4:      isz R10,loop3           ; next nibble value (0-F)
            isz R7,loop             ; next data RAM character (0-F)
            
; RAM status characters 0-3  
            fim P0,lo(msg2)         ; print "Testing status"
txt2:       fin P1                  ; fetch the character pointed to by P0 into P1
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,txt2             ; not yet at the end of the string, go back for the next character            
  
status:     ld R10                  ; start with 0
            wr0                     ; write nibble to status character 0
            wr1                     ; write nibble to status character 1
            wr2                     ; write nibble to status character 2
            wr3                     ; write nibble to status character 3            
            
            rd0                     ; read nibble from status character 0
            clc
            sub R10                 ; compare by subtraction
            jcn z,status1           ; jump if the nibble read matches the nibble written
            ldm 0                   ; else, print the error message indicating status character 0
            jun statuserr

status1:    rd1                     ; read nibble from status character 1
            clc
            sub R10                 ; compare by subtraction
            jcn z,status2           ; jump if the nibble read matches the nibble written
            ldm 1                   ; else, print the error message indicating status character 1
            jun statuserr

status2:    rd2                     ; read nibble from status character 2
            clc
            sub R10                 ; compare by subtraction
            jcn z,status3           ; jump if the nibble read matches the nibble written
            ldm 2                   ; else, print the error message indicating status character 2
            jun statuserr

status3:    rd3                     ; read nibble from status character 3
            clc
            sub R10                 ; compare by subtraction
            jcn z,status4           ; jump if the nibble read matches the nibble written
            ldm 3                   ; else, print the error message indicating status character 3
            jun statuserr
            
status4:    isz R10,status          ; next nibble (0-F)
            
            inc R6                  ; next data RAM register (0-3)
            ld R6
            clc
            sub R8                  ; compare by subtraction to RAM end
            jcn nz,loop
            
            fim P0,lo(msg3)         ; print "Passed"
txt3:       fin P1                  ; fetch the character pointed to by P0 into P1
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,txt3             ; not yet at the end of the string, go back for the next character            
            
            jun ramtest
            
msg0:       data CR,LF,"Testing data RAM ",0 
msg1:       data "Testing ",0           
msg2:       data "Testing status characters",CR,LF,0           
msg3:       data CR,LF,"Passed",CR,LF,LF,0
            org 0100H
;-----------------------------------------------------------------------------------------
; turn on the error LED and print the RAM error message
; print the RAM location where the error occurred as two hex digits:
; the first hex digit is the RAM register number, the second digit is the RAM character number.
;-----------------------------------------------------------------------------------------
ramerr:     fim P0,lo(ramerrtxt)
ramerr1:    fin P1                  ; fetch the character pointed to by P0 into P1
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,ramerr1          ; not yet at the end of the string, go back for the next character
            ld R6                   ; R6 holds the RAM register number
            xch R0
            ld R7                   ; R7 holds the RAM character number
            xch R1
            jms print2hex           ; print RAM register number and character number as two hex digits
            fim P1,'H'
            jms putchar
            jms newline
            
            fim P0,LEDPORT
            src P0
            ldm 1000B
            wmp                     ; turn on the LED connected to bit 3 output of RAM chip 1            
            
here:       jun here                ; halt and catch fire

ramerrtxt:  data CR,LF,LF
            data "Data RAM error at ",0
            
;-----------------------------------------------------------------------------------------
; turn on the error LED and print the RAM error message
; print the RAM location where the error occurred as two hex digits:
; the first hex digit is the RAM register number, the second digit is the RAM status character number.
;-----------------------------------------------------------------------------------------
statuserr:  fim P0,lo(statuserrtxt)
            xch R7                  ; put the status character number into R7
            jun ramerr1

statuserrtxt:data CR,LF,LF
            data "Status RAM error at ",0   

;-----------------------------------------------------------------------------------------
; prints the contents of P0 as two hex digits
;-----------------------------------------------------------------------------------------
print2hex:  ld R0                   ; most significant nibble
            jms print1hex
            ld R1                   ; least significant nibble, fall through to the print1hex subroutine below

;-----------------------------------------------------------------------------------------
; print the accumulator as one hex digit, destroys contents of the accumulator
;-----------------------------------------------------------------------------------------
print1hex:  fim P1,30H              ; R2 = 3, R3 = 0;
            clc
            daa                     ; for values A-F, adds 6 and sets carry
            jcn cn,print1hex1       ; no carry means 0-9
            inc R2                  ; R2 = 4 for ascii 41h (A), 42h (B), 43h (C), etc
            iac                     ; we need one extra for the least significant nibble
print1hex1: xch R3                  ; put that value in R3, fall through to the putchar subroutine below
            jun putchar
            
;-----------------------------------------------------------------------------------------
; position the cursor to the start of the next line
; uses P1.
;-----------------------------------------------------------------------------------------
newline:    fim P1,CR
            jms putchar
            fim P1,LF
            jun putchar

;-----------------------------------------------------------------------------------------
; This function is used by all the text string printing functions. If the character in P1 is zero indicating
; the end of the string, returns with accumualtor = 0. Otherwise prints the character and increments
; P0 to point to the next character in the string then returns with accumulator = 1.
; uses P0, P1, P6 and P7
;-----------------------------------------------------------------------------------------
txtout:     ld R2                   ; load the most significant nibble into the accumulator
            jcn nz,txtout1          ; jump if not zero (not end of string)
            ld  R3                  ; load the least significant nibble into the accumulator
            jcn nz,txtout1          ; jump if not zero (not end of string)
            bbl 0                   ; end of text found, branch back with accumulator = 0

txtout1:    jms putchar             ; print the character in P1
            inc R1                  ; increment least significant nibble of pointer
            ld R1                   ; get the least significant nibble of the pointer into the accumulator
            jcn zn,txtout2          ; jump if zero (no overflow from the increment)
            inc R0                  ; else, increment most significant nibble of the pointer
txtout2:    bbl 1                   ; not end of text, branch back with accumulator = 1

            org 0200H
;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 serial function 'putchar'
; send the character in P1 to the console serial port (the least significant bit of port 0) 
; in addition to P1 (R2,R3) also uses P7 (R14,R15)
; preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar:    fim P7,SERIALPORT
            src P7                  ; set port address
            ldm 16-5
            xch R14                 ; 5 bits (start bit plus bits 0-3)
            ld R3
            clc                     ; clear carry to make the start bit
            ral
            
; send 5 bits; the start bit and bits 0-3. each bit takes 9 cycles
putchar1:   nop
            nop
            nop
            nop
            nop
            wmp
            rar
            isz R14, putchar1

            ldm 16-5                ; 5 bits (bits 4-8 plus stop bit)
            xch R14
            ld R2
            stc
            nop
            nop

; send 5 bits; bits 4-7 and the stop bit. each bit takes 10 cycles
putchar2:   wmp
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
            
