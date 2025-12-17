                PAGE 0                          ; suppress page headings in ASW listing file
                cpu 4004
                
;---------------------------------------------------------------------------------------------------------------------------------
; Copyright 2022 Jim Loos
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
    
;--------------------------------------------------------------------------------------------------
; Nim game firmware for the Intel 4004 Single Board Computer.
; Requires the use of a terminal emulator connected to the SBC
; set for 9600 bps, no parity, 8 data bits, 1 stop bit.
; Assemble with the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;----------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------------------------------------
; This is a simple game where the second player --- if they know the trick --- always wins.
;
; The game has only 3 rules:
;
; 1. start with a pile of 12 tokens.
; 2. each player takes 1, 2, or 3 tokens from the pile in turn.
; 3. the player who takes the last token from the pile wins.
;
; to win every time, the second player simply takes 4 minus the number the first
; player took. so if the first player takes 1, the second player should take 3. 
; if the first player takes 2, the second player should take 2, if the first player
; takes 3, the second player should take 1.
;----------------------------------------------------------------------------------------------------

                include "bitfuncs.inc"  ; Include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).
                include "reg4004.inc"   ; Include 4004 register definitions.

CR              equ 0DH
LF              equ 0AH
ESCAPE          equ 1BH

; I/O port addresses
SERIALPORT      equ 00H                 ; Address of the serial port. The least significant bit of port 00 is used for serial output.
LEDPORT         equ 40H                 ; Address of the port used to control the red LEDs. "1" turns the LEDs on.
GPIO            equ 80H                 ; 4265 General Purpose I/O device address

; RAM register addresses
CHIP0REG0       equ 00H                 ; 4002 data ram chip 0, register 0 16 main memory characters plus 4 status characters
CHIP0REG1       equ 10H                 ; 4002 data ram chip 0, register 1  "   "    "         "       "  "    "       "
CHIP0REG2       equ 20H                 ; 4002 data ram chip 0, register 2  "   "    "         "       "  "    "       "
CHIP0REG3       equ 30H                 ; 4002 data ram chip 0, register 3  "   "    "         "       "  "    "       "
CHIP1REG0       equ 40H                 ; 4002 data ram chip 1, register 0  "   "    "         "       "  "    "       "
CHIP1REG1       equ 50H                 ; 4002 data ram chip 1, register 1  "   "    "         "       "  "    "       "
CHIP1REG2       equ 60H                 ; 4002 data ram chip 1, register 2  "   "    "         "       "  "    "       "
CHIP1REG3       equ 70H                 ; 4002 data ram chip 1, register 3  "   "    "         "       "  "    "       "

token_heap      equ CHIP0REG0           ; number of tokens in the 'heap'
players_take    equ CHIP0REG1           ; number of tokens taken by the player
computers_take  equ CHIP0REG2           ; number of tokens taken by the computer

                org 0000H               ; beginning of 2732 EPROM
;--------------------------------------------------------------------------------------------------
; Power-on-reset Entry
;--------------------------------------------------------------------------------------------------
                nop                     ; "To avoid problems with power-on reset, the first instruction at
                                        ; program address 0000 should always be an NOP." (don't know why)
reset:          fim P0,SERIALPORT
                src P0
                ldm 1
                wmp                     ; set RAM serial output high to indicate 'MARK'

                fim P0,GPIO             ; address of the 4265 GPIO device
                src P0
                ldm 0111B               ; ports W, X and Y as inputs, port Z as output
                wmp                     ; program the 4265 for mode 7 (three 4-bit input ports, one 4-bit output port)
                ldm 1
                wr3                     ; set alternate serial output (pin 14 of 4265) high to indicate 'MARK'
                
                fim P0,LEDPORT
                src P0
                ldm 0
                wmp                     ; write data to RAM LED output port, set all 4 outputs low to turn off all four LEDs                                            
                
                jun subtr_game

                org 0100H
;--------------------------------------------------------------------------------------------------
; Simple game of subtraction
;--------------------------------------------------------------------------------------------------
subtr_game:     fim P2,token_heap       ; initialize the token heap
                jms clrram
                src P2                  ; least significant digit
                ldm 2
                wrm                     ; store the units digit of '12'
                inc R5
                src P2
                ldm 1
                wrm                     ; store the tens digit of '12'

                jms intro               ; print the introduction
subtr_game0:    jms prnremaining        ; print the number of tokens remaining on the heap
subtr_game1:    jms prompt              ; prompt the player for the number of tokens to remove
                fim P2,players_take
                jms clrram              ; clear the players_take register
                jms gettake             ; get the player's input
                jcn zn,subtr_game1      ; non-zero means an invalid number, go back and try again
                jms newline
                fim P1,token_heap
                fim P2,players_take
                jms subtract            ; token_heap = token_heap - players_take
                jms prnremaining        ; print the number of tokens remaining on the heap

                fim P2,computers_take
                jms clrram              ; clear the computers_take register
                src P2
                ldm 4
                wrm                     ; initialize the computers_take register to '4'
                fim P1,computers_take
                fim P2,players_take
                jms subtract            ; computers_take = 4 - players_take
                jms comptake            ; print "The computer takes "
                fim P3,computers_take
                jms prndigits           ; print the number of tokens the computer takes
                jms newline

                fim P1,token_heap       ; tokens remaining
                fim P2,computers_take   ; computer's take
                jms subtract            ; token_heap = token_heap - computers_take
                fim P2,token_heap
                jms checkzero           ; check to see if there are zero tokens remaining (computer won)
                jcn zn,subtr_game0      ; no, then it's the player's turn
                jms compwins            ; yes, print "The computer wins!"

                jms again               ; prompt "Play again? (Y/N)"
                jms getchar
                fim P3,'Y'              ; is it "Y"
                jms compare
                jcn z,subtr_game        ; go back for another game
                fim P3,'y'              ; is it "y"
                jms compare
                jcn z,subtr_game        ; go back for another game
                jms goodbye             ; else, print "Bye."
here:           jun here                ; wait here forever...

;--------------------------------------------------------------------------------------------------
; print the number of tokens remaining on the heap
;--------------------------------------------------------------------------------------------------
prnremaining:   jms newline
                fim P3,token_heap
                src P3
                rdm
                xch R3                  ; least significant digit of token heap now in R3
                inc R7                  ; next character in token_heap register
                src P3
                rdm
                xch R2                  ; P1 now contains token_heap
                fim P3,01               ; P3 contains 1
                jms compare             ; compare P1 to P3 (compare token_heap to 1)
                jcn nz,prnremaining1    ; jump if token remaining on the heap does not equal 1
                jun remaining1          ; else, print "There is 1 token remaining."

prnremaining1:  fim P3,token_heap
                jms prndigits           ; print the number of tokens in the heap
                jun remaining3          ; print " tokens remaining."

;--------------------------------------------------------------------------------------------------
; get the number of tokens to take from the player.
; if the number is 1-3, store it in players_take and return 0. else return 1.
;--------------------------------------------------------------------------------------------------
gettake:        jms getchar             ; get the player's input
                jms putchar             ; echo the character
                ldm 3
                clc                     ; clear carry in preparation for 'sub' instruction
                sub R2                  ; compare the most significant nibble to 3 by subtraction
                jcn zn,gettake1         ; jump if the most significant nibble of the character input is not 3 (not a number 30-39H, ASCII '0'-'9')
                ld R3                   ; least significant nibble now in A
                jcn z,gettake1          ; jump if the least significant nibble is 0 (the number is zero)
                xch R3                  ; else, save the number in R3
                ldm 4
                xch R4                  ; R4 now contains 4
                ld R3                   ; A now contains the number
                clc
                sub R4                  ; subtract 4 from the number
                jcn c,gettake1          ; jump if the number entered is greater than 3
                ld R3                   ; else, load the number back into A
                fim P1,players_take     ; P1 points to the register
                src P1
                wrm                     ; save the number in the player's take register
                bbl 0
gettake1:       bbl 1

;-------------------------------------------------------------------------------
; returns 0 if the RAM register pointed to by P2 is zero.
;-------------------------------------------------------------------------------
checkzero:      src P2
                rdm
                jcn nz,checkzero1       ; jump if the RAM contents are not zero
                isz R5,checkzero        ; else, loop back for all 16 characters
                bbl 0                   ; return 0 to indicate zero
checkzero1:     bbl 1                   ; return 1 to indicate not zero

;-------------------------------------------------------------------------------
; print the contents of RAM register pointed to by P3 as a 16 digit decimal number.
; status character 0 serves as a leading zero flag (1 means skip leading zeros). 
; the digits are stored in RAM from right to left i.e least significant digit is at
; 00H and the most significant digit is at 0FH.
;-------------------------------------------------------------------------------
prndigits:      ldm 0
                xch R10                 ; R10 is the loop counter (0 gives 16 times thru the loop for all 16 digits)
                ldm 0FH
                xch R7                  ; make P3 0FH (or 1FH or 2FH, etc.)
                ldm 1
                src P3
                wr0                     ; set the leading zero flag at status character 0
prndigits1:     src P3
                ld R7
                jcn zn,prndigits2       ; jump if this is not the last digit
                ldm 0
                wr0                     ; since this is the last digit, clear the leading zero flag
prndigits2:     rd0                     ; get the leading zero flag from status character 0
                rar                     ; rotate the flag into carry
                rdm                     ; read the digit to be printed
                jcn zn,prndigits3       ; jump if this digit is not zero
                jcn c,prndigits4        ; this digit is zero, jump if the leading zero flag is set
prndigits3:     xch R3                  ; this digit is not zero OR the leading zero flag is not set. put the digit as least significant nibble into R3
                ldm 3
                xch R2                  ; most significant nibble ("3" for ASCII characters 30H-39H)
                jms putchar             ; print the ASCII code for the digit
                src P3
                ldm 0
                wr0                     ; reset the leading zero flag at status character 0

prndigits4:     ld  R7                  ; least significant nibble of the pointer to the digit
                dac                     ; next digit
                xch R7
                isz R10,prndigits1      ; loop 16 times (print all 16 digits)
                bbl 0                   ; finished with all 16 digits

                org 0200H
;--------------------------------------------------------------------------------------------------
; Multi-digit subtraction function: P1 points to the minuend. P2 points to subtrahend.
; The subtrahend is subtracted from the minuend. The difference replaces the minuend.
; Returns 0 if the difference is positive. Returns 1 if the difference is negative.
;--------------------------------------------------------------------------------------------------
subtract:       ldm 0
                xch R11                 ; R11 is the loop counter (0 gives 16 times thru the loop for 16 digits)
                stc                     ; set carry = 1
subtract1:      tcs                     ; accumulator = 9 or 10
                src P2                  ; select the subtrahend
                sbm                     ; produce 9's or l0's complement
                clc                     ; set carry = 0
                src P1                  ; select the minuend
                adm                     ; add minuend to accumulator
                daa                     ; adjust accumulator
                wrm                     ; write result to replace minuend
                inc R3                  ; address next digit of minuend
                inc R5                  ; address next digit of subtrahend
                isz R11,subtract1       ; loop back for all 16 digits
                jcn c,subtract2         ; carry set means no underflow from the 16th digit
                bbl 1                   ; overflow, the difference is negative
subtract2:      bbl 0                   ; no overflow, the difference is positive

;-------------------------------------------------------------------------------
; clear RAM register pointed to by P2.
;-------------------------------------------------------------------------------
clrram:         ldm 0
clrram1:        src P2
                wrm                     ; write zero into RAM
                isz R5,clrram1          ; 16 times (zero all 16 characters)
                wr0                     ; clear all 4 status characters
                wr1
                wr2
                wr3
                bbl 0

;--------------------------------------------------------------------------------------------------
; Compare the contents of P1 (R2,R3) with the contents of P3 (R6,R7).
; Returns 0 if P1 = P3.
; Returns 1 if P1 < P3.
; Returns 2 if P1 > P3.
; Overwrites the contents of P3.
; Adapted from code in the "MCS-4 Micro Computer Set Users Manual" on page 166:
;--------------------------------------------------------------------------------------------------
compare:        clc                     ; clear carry before "subtract with borrow" instruction
                xch R6                  ; contents of R7 (high nibble of P3) into accumulator
                sub R2                  ; compare the high nibble of P1 (R2) to the high nibble of P3 (R6) by subtraction
                jcn cn,greater          ; no carry means that R2 > R6
                jcn zn,lesser           ; jump if the accumulator is not zero (low nibbles not equal)
                clc                     ; clear carry before "subtract with borrow" instruction
                xch R7                  ; contents of R6 (low nibble of P3) into accumulator
                sub R3                  ; compare the low nibble of P1 (R3) to the low nibble of P3 (R7) by subtraction
                jcn cn,greater          ; no carry means R3 > R7
                jcn zn,lesser           ; jump if the accumulator is not zero (high nibbles not equal)
                bbl 0                   ; 0 indicates P1=P3
lesser:         bbl 1                   ; 1 indicates P1<P3
greater:        bbl 2                   ; 2 indicates P1>P3

;-----------------------------------------------------------------------------------------
; position the cursor to the start of the next line
;-----------------------------------------------------------------------------------------
newline:        fim P1,CR
                jms putchar
                fim P1,LF
                jun putchar

;-----------------------------------------------------------------------------------------
; This function is used by all the text string printing functions. If the character in P1 is zero indicating
; the end of the string, returns with accumualtor = 0. Otherwise prints the character and increments
; P0 to point to the next character in the string then returns with accumulator = 1.
;-----------------------------------------------------------------------------------------
txtout:         ld R2                   ; load the most significant nibble into the accumulator
                jcn nz,txtout1          ; jump if not zero (not end of string)
                ld  R3                  ; load the least significant nibble into the accumulator
                jcn nz,txtout1          ; jump if not zero (not end of string)
                bbl 0                   ; end of text found, branch back with accumulator = 0

txtout1:        jms putchar             ; print the character in P1
                inc R1                  ; increment least significant nibble of pointer
                ld R1                   ; get the least significant nibble of the pointer into the accumulator
                jcn zn,txtout2          ; jump if zero (no overflow from the increment)
                inc R0                  ; else, increment most significant nibble of the pointer
txtout2:        bbl 1                   ; not end of text, branch back with accumulator = 1

; serial I/O functions putchar and getchar
;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 serial function 'putchar'
; send the character in P1 to the console serial port (the least significant bit of port 0) 
; in addition to P1 (R2,R3) also uses P7 (R14,R15)
; preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar:        fim P7,SERIALPORT
                src P7                  ; set port address
                ldm 16-5
                xch R14                 ; 5 bits (start bit plus bits 0-3)
                ld R3
                clc                     ; clear carry to make the start bit
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

                ldm 16-5                ; 5 bits (bits 4-8 plus stop bit)
                xch R14
                ld R2
                stc
                nop
                nop

; send 5 bits; bits 4-7 and the stop bit. each bit takes 10 cycles
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
                
;-----------------------------------------------------------------------------------------
; 9600 bps N-8-1 serial function 'getchar'
; wait for a character from the serial input port (TEST input on the 4004 CPU).
; NOTE: the serial input line is inverted by hardware before it gets to the TEST input;
; i.e. TEST=0 when the serial line is high and TEST=1 when the serial line is low,
; therefore the sense of the bit needs to be inverted in software. 
; returns the 8 bit received character in P1 (R2,R3). also uses P7 (R14,R15).
;-----------------------------------------------------------------------------------------              
getchar:        jcn t,$                 ; wait for serial input to go low (the start bit)
getchar0:       ldm 16-4                ; 4 bits
                xch R14                 ; R14 is the counter for the first four bits (0-3)
                ldm 16-3
                xch R15
                isz R15,$               ; 12 cycles between start bit and bit 0
; receive bits 0-3
getchar1:       jcn tn,getchar2         ; jump if the test input==1
                stc                     ; if test input==0, then cy=1
                jun getchar3
getchar2:       clc                     ; if test input==1, then cy=0
                jun getchar3
getchar3:       rar                     ; rotate carry into accumulator
                nop                     ; 9 cycles/bit (error=-0.645 cycle/bit)
                isz r14, getchar1       ; repeat until all 4 bits (0-3) received.
                xch R3                  ; save received bits 0-3 in R3
                ldm 16-4
                xch R14                 ; R14 is the counter for the next 4 bits (bits 4-8)
; receive bits 4-8                                    
getchar4:       jcn tn,getchar5         ; jump if the test input==1
                stc                     ; if test input==0, then cy=1
                jun getchar6
getchar5:       clc                     ; if test input==1, then cy=0
                nop
                nop
getchar6:       rar                     ; rotate received bit into accumulator
                nop                     ; 9 cycles/bit
                isz R14,getchar4        ; repeat until 4 bits (4-8) received.
                xch R2                  ; save received bits 4-7 in R2
                nop
                nop
; check the stop bit...
                jcn tn,$                ; wait for serial input to go high (the stop bit)
                bbl 0
                
                org 0300H
;-----------------------------------------------------------------------------------------
; printing functions for the game. 
; these functions and the text they reference must be on the same page.
;-----------------------------------------------------------------------------------------
page2print:     fin P1                  ; fetch the character pointed to by P0 into P1
                jms txtout              ; print the character, increment the pointer to the next character
                jcn zn,page2print       ; go back for the next character
                bbl 0

intro:          fim P0,lo(introtxt)
                jun page2print

again:          fim P0,lo(againtxt)
                jun page2print

goodbye:        fim P0,lo(goodbyetxt)
                jun page2print

introtxt:       data CR,LF,LF
                data "This is a simple game of subtraction. We start with a pile of",CR,LF
                data "of 12 tokens. You and the computer take turns removing 1, 2 or 3",CR,LF
                data "tokens from the pile. Whoever takes the last token wins.",CR,LF,LF
                data "You move first.",CR,LF,0

againtxt:       data CR,LF,"Play again? (Y/N)",0

goodbyetxt      data CR,LF,"Bye.",CR,LF,0

                org 0400H
;-----------------------------------------------------------------------------------------
; more printing functions. 
; these functions and the text they reference must be on the same page.
;-----------------------------------------------------------------------------------------
page3print:     fin P1                  ; fetch the character pointed to by P0 into P1
                jms txtout              ; print the character, increment the pointer to the next character
                jcn zn,page3print       ; go back for the next character
                bbl 0

prompt:         fim P0,lo(prompttxt)
                jun page3print

remaining1:     fim P0,lo(remaining1txt)
                jun page3print

remaining3:     fim P0,lo(remaining3txt)
                jun page3print

comptake:       fim P0,lo(comptaketxt)
                jun page3print

compwins:       fim P0,lo(compwinstxt)
                jun page3print

remaining1txt:  data "1 token remaining.",0
remaining3txt:  data " tokens remaining.",0
prompttxt:      data CR,LF,"How many tokens do you want to remove? (1-3) ",0
comptaketxt     data CR,LF,"The computer takes ",0
compwinstxt     data CR,LF,"The computer wins!",CR,LF,0
copyrighttxt:   data CR,LF,"Copyright Jim Loos, 2021. Assembled on ",DATE," at ",TIME,".",CR,LF,0

                end

