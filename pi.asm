            PAGE 0                      ; suppress page headings in ASW listing file

;---------------------------------------------------------------------------------------------------
;
; Calculating Pi using the inverse tangent formula with Intel 4004 CPU (MCS-4 system) to 16 digits.
;
; Written by Lajos Kintli. https://4004.com/
;
; (version 2023.10.29)
;
;---------------------------------------------------------------------------------------------------
;
; Edited to assemble with the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/ 
; and modified to print the result to the serial port instead of using a seven segment LED display.
; (Jim Loos 12/13/2025)
;
;---------------------------------------------------------------------------------------------------
;
; Used formulas:
;
;       Euler:          Pi/4 = arc tg (1/2) + arc tg (1/3)
;
;       Better:         Pi/4 = 2 * arc tg (1/3) + arc tg (1/7)
;
;       Machin's:       Pi/4 = 4 * arc tg (1/5) - arc tg (1/239)
;
; Inverse tangent is calculated using the Taylor polynomial: 
;
;       arc tg(x)=x - x^3/3 + x^5/5 - x^7/7 + x^9/9 - x^11/11 + ...,
;
; what works for an integer reciprocal in the below way (x=1/n):
;  
;       arc tg(1/n)=1/n - 1/n^3/3 + 1/n^5/5 - 1/n^7/7 + 1/n^9/9 - 1/n^11/11 + ...
;
; Three high level registers are implemented, REG0 is for the sum, REG1 is for the next item
; in Taylor polynomial: 1/n^(2k+1)/(2k+1), while REG2 is for 1/n^(2k+1). 
;
; Precision is 16*4 bit in binary. During the arc tg calculation the integer part of the number
; is zero, only fractional part is stored in memory cells (decimal point is fixed before the first
; memory cell). 
;
; REG2 is started with 1/n, and divided by n*n at every iterations. REG1 is coming
; from REG2 divided by (2k+1).
;
; Binary result is converted to decimal at the end for 16 digits behind the decimal point
;
; Two divide routines are implemented, first is slightly faster and handles only 4 bit
; divider, while the other accepts 8 bit divider.
;
; Register usage:
;
; R0,R1         RAM pointer (target register)
; R2,R3         RAM pointer (source register)
; R4,R5         divider
; R6,R7         used for divide
; R8            length counter
; R9            bit counter
; R10           next 4 bits
; R11           sign bit or digit
; R12,R13:      2 k + 1
; R14,R15:      n*n if n=2,3,7 or n=239 (highest bit decides if it is n or n*n)
; 
; RAM 00-0F:    REG0: sum
; RAM 10-1F:    REG1: 1/n^(2k+1)/(2k+1)
; RAM 20-2F:    REG2: 1/n^(2k+1)
; RAM 30-3F:    decimal result
;
; Result RAM0 content:
;       0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 - 0 0 0 0
;       0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 - 0 0 0 0
;       2 4 3 F 6 A 8 8 8 5 A 3 0 8 D 8 - 0 0 0 0       <-- fractional in hex
;       1 4 1 5 9 2 6 5 3 5 8 9 7 9 3 2 - 0 0 0 3       <-- decimal
;
;---------------------------------------------------------------------------------------------------
                cpu 4040                ; Tell the Macro Assembler AS that this source is for the Intel 4040
                
                include "bitfuncs.inc"  ; bit functions 
                include "reg4004.inc"   ; 4004 register definitions.

CR              equ 0DH
LF              equ 0AH
CLS             equ "\e[2J\e[H"         ; VT100 escape sequence to clear screen and home cursor

; I/O port addresses
SERIALPORT      equ 00H                 ; address of the serial port. The least significant bit of port 00 is used for serial output.
LEDPORT         equ 40H                 ; address of the port used to control the red LEDs. "1" turns the LEDs on.
GPIO            equ 80H                 ; 4265 General Purpose I/O device address

; 4265 Modes:   WMP                 Port:   W   X   Y   Z
GPIOMODE0       equ 0000B               ;   In  In  In  In (reset)
GPIOMODE4       equ 0100B               ;   Out Out Out Out
GPIOMODE5       equ 0101B               ;   In  Out Out Out
GPIOMODE6       equ 0110B               ;   In  In  Out Out
GPIOMODE7       equ 0111B               ;   In  In  In  Out

; Set one of the below definitions to 1!
EULER           EQU     0
BETTER          EQU     0
MACHIN          EQU     1

                org     0000H

reset:          nop                    ; "To avoid problems with power-on reset, the first instruction at
                                       ; program address 0000 should always be an NOP." (don't know why)
                fim P0,SERIALPORT
                src P0
                ldm 1
                wmp                    ; set RAM serial output high to indicate 'MARK'
                
               fim P6,079H             ; 250 milliseconds delay for serial port
               fim P7,06DH
reset1:        isz R12,reset1
               isz R13,reset1
               isz R14,reset1
               isz R15,reset1
                

                jms banner              

                fim P0,LEDPORT
                src P0
                ldm 0
                wmp                    ; write zeros to RAM LED output port, set all 4 outputs low to turn off all four LEDs
                
                fim     P0,00H
                jms     storez         ; clear RAM 00-0F                

                IF EULER               ; arc tg (1/2) + arc tg (1/3)
                fim     P2,3           ; prepare 3 & 9
                fim     P7,9
                jms     arc_tg
                fim     P2,2           ; prepare 2 & 4
                fim     P7,4
                jms     arc_tg

                ELSEIF BETTER          ; 2 * arc tg (1/3) + arc tg (1/7)
                fim     P2,3           ; prepare 3 & 9
                fim     P7,9
                jms     arc_tg
                jms     mul2
                fim     P2,7           ; prepare 4 & 49
                fim     P7,49
                jms     arc_tg

                ELSEIF MACHIN          ; 4 * arc tg (1/5) - arc tg (1/239)
                fim     P2,5           ; prepare 5 & 25
                fim     P7,25
                jms     arc_tg
                jms     mul2
                jms     mul2
                fim     P2,239         ; prepare 239 
                fim     P7,239
                ldm     1
                jms     arc_tg_m
                ENDIF

                ldm     0              ; clear the integer digit
                xch     R11
                jms     mul2           ; multiply by 4
                jms     mul2
                fim     P0,20H         ; save Pi in binary
                fim     P1,00H
                jms     mov_xy

;------------------------------------------------------------------------------
; convert from binary to decimal
;------------------------------------------------------------------------------
                fim     P2,30H
                src     P2
                xch     R11              
                wr0                    ; write the first digit of Pi into status character
mul10_loop:     ldm     0
                xch     R11
                xch     R5
                dac
                xch     R5
                fim     P0,10H         ; multiply by 10 = 2*(2*2+1)
                fim     P1,00H                   
                jms     mov_xy          
                jms     mul2
                jms     mul2
                fim     P0,00H
                fim     P1,10H                   
                jms     add_xy
                tcc
                add     R11
                xch     R11
                jms     mul2
                xch     R11
                src     P2             ; write the result
                wrm
                ld      R5
                jcn     nz,mul10_loop
                fim     P0,00H         ; clean the remaining part of decimal c
                jms     storez
                inc     R0
                jms     storez

;------------------------------------------------------------------------------
; print the result to the serial port
;------------------------------------------------------------------------------
                fim     P3,30H         ; P3 points to the RAM register where Pi is stored
                src     P3
                rd0                    ; read the integer part of Pi from the status character    
                xch     R3
                ldm     3
                xch     R2             ; convert from binary to ASCII
                jms     putchar        ; print the integer part of Pi
                fim     P1,'.'
                jms     putchar        ; print the decimal point
                jms     prndigits      ; print the fractional part of Pi
                jms     newline
halt:           jun     halt

;-------------------------------------------------------------------------------
; Print the contents of RAM register pointed to by P3 as a 16 digit decimal number. R11
; serves as a leading zero flag (1 means skip leading zeros). The digits are stored
; in RAM from right to left i.e. the most significant digit is at location 0FH,
; therefore it's the first digit printed. The least significant digit is at location
; 00H, so it's the last digit printed.
;-------------------------------------------------------------------------------
prndigits:      ldm 16-16
                xch R10                ; R10 is the loop counter (0 gives 16 times thru the loop for all 16 digits)
                ldm 0FH
                xch R7                 ; make P3 0FH (point to the most significant digit)
                ldm 1
                xch R11                ; set the leading zero flag ('1' means do not print digit)
prndigits1:     ld R7
                jcn zn,prndigits2      ; jump if this is not the last digit
                ldm 0
                xch R11                ; since this is the last digit, clear the leading zero flag
prndigits2:     ld R11                 ; get the leading zero flag
                rar                    ; rotate the flag into carry
                src P3                 ; use P3 address for RAM reads
                rdm                    ; read the digit to be printed from RAM
                jcn zn,prndigits3      ; jump if this digit is not zero
                jcn c,prndigits4       ; this digit is zero, jump if the leading zero flag is set
                
prndigits3:     xch R3                 ; this digit is not zero OR the leading zero flag is not set. put the digit as least significant nibble into R3
                ldm 3
                xch R2                 ; most significant nibble ("3" for ASCII characters 30H-39H)
                jms putchar            ; print the ASCII code for the digit
                ldm 0
                xch R11                ; reset the leading zero flag
prndigits4:     ld  R7                 ; least significant nibble of the pointer to the digit
                dac                    ; decrement to point to the next digit
                xch R7
                isz R10,prndigits1     ; loop 16 times (print all 16 digits)
                bbl 0                  ; finished with all 16 digits

;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 serial function 'putchar'
; send the character in P1 to the console serial port (the least significant bit of port 0) 
; in addition to P1 (R2,R3) also uses P7 (R14,R15)
; preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar:        fim P7,SERIALPORT
                src P7                 ; set port address
                ldm 16-5
                xch R14                ; R14 is the counter for 5 bits (start bit plus bits 0-3)
                ld R3                  ; load bits 0-3 from R3
                clc                    ; clear carry to make the start bit
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
                ldm 16-5               ; R14 is the counter for 5 bits (bits 4-7 plus stop bit)
                xch R14
                ld R2                  ; load bits 4-7 from R2
                stc                    ; carry will eventually become the start bit
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
                rar                    ; rotate next bit into position
                isz R14, putchar2      
                bbl 0
                
;-----------------------------------------------------------------------------------------
; position the cursor to the start of the next line
;-----------------------------------------------------------------------------------------
newline:        fim P1,CR
                jms putchar
                fim P1,LF
                jun putchar

;-----------------------------------------------------------------------------------------
; This function is used by all the text string printing functions. If the character in P1 
; is zero indicating the end of the string, returns 0. Otherwise prints the character and 
; increments P0 to point to the next character in the string then returns 1.
;-----------------------------------------------------------------------------------------
txtout:         ld R2                  ; load the most significant nibble into the accumulator
                jcn nz,txtout1         ; jump if not zero (not end of string)
                ld  R3                 ; load the least significant nibble into the accumulator
                jcn nz,txtout1         ; jump if not zero (not end of string)
                bbl 0                  ; end of text found, branch back with accumulator = 0

txtout1:        jms putchar            ; print the character in P1
                inc R1                 ; increment least significant nibble of pointer
                ld R1                  ; get the least significant nibble of the pointer into the accumulator
                jcn zn,txtout2         ; jump if zero (no overflow from the increment)
                inc R0                 ; else, increment most significant nibble of the pointer
txtout2:        bbl 1                  ; not end of text, branch back with accumulator = 1

printtxt:       fin P1                 ; fetch the character pointed to by P0 into P1
                jms txtout             ; print the character, increment the pointer to the next character
                jcn zn,printtxt        ; go back for the next character
                bbl 0

banner:         fim P0,lo(bannertxt)
                jun printtxt

bannertxt:      data CLS,"Pi = ",0


                org     0100H

;------------------------------------------------------------------------------
; ADD:  [DST] = [DST] + [SRC]
;------------------------------------------------------------------------------
add_xy:         clc
add_loop:       src     P1
                rdm
                src     P0
                adm
                wrm
                inc     R3
                isz     R1,add_loop
                bbl     0

;------------------------------------------------------------------------------
; SUB:  [DST] = [DST] - [SRC]
;------------------------------------------------------------------------------
sub_xy:         clc
sub_loop:       src     P0
                rdm
                src     P1
                sbm
                cmc
                src     P0
                wrm
                inc     R3
                isz     R1,sub_loop
                bbl     0

;------------------------------------------------------------------------------
; FILL: [DST] = value
;------------------------------------------------------------------------------
storez:         ldm     0                       
store:          src     P0
                wrm
                isz     R1,store
                bbl     0
                
;------------------------------------------------------------------------------
; MOV:  [DST] = [SRC]
;------------------------------------------------------------------------------
mov_xy:
mov_loop:       src     P1
                rdm
                src     P0
                wrm
                inc     R3
                isz     R1,mov_loop
                bbl     0

;------------------------------------------------------------------------------
; multiply by 2 - REG0 = 2 * REG0,  extra bits are in R11
;------------------------------------------------------------------------------
mul2:           fim     P0,00H
                fim     P1,00H
                jms     add_xy
                ld      R11
                ral
                xch     R11
                bbl     0       
                
;------------------------------------------------------------------------------
; Divide by a 4 bit value in R5:        [DST] = [DST] / R5
;------------------------------------------------------------------------------
div_r:          clb
div_r_set:      fim     P4,0
div_r_dloop:    xch     R1             ; data loop
                dac
                xch     R1
                src     P0
                xch     R10            ; fetch next 4 bits into r7
                rdm
                xch     R10
                xch     R9             ; 4 bit counter
                ldm     0CH
                xch     R9
div_r_bloop:    clc                    ; bit loop
                xch     R10
                ral                    ; rotate accu - regA left by one bit
                xch     R10
                ral
                jcn     c,div_r_sub
                sub     R5             ; try to sub the number
                jcn     c,div_r_sub_ok
                add     R5             ; add back the number
                jun     div_r_skip

div_r_sub:      clc
                sub     R5             ; sub the number in case of carry
div_r_sub_ok:   inc     R10
div_r_skip:     isz     R9,div_r_bloop
                xch     R10
                wrm
                xch     R10
                isz     R8,div_r_dloop
                bbl     0

;------------------------------------------------------------------------------
; Divide 1 by an 8 bit value in R4,R5: REG2 = 1 / R4,R5
;------------------------------------------------------------------------------
div_x_one       fim     P0,20H
                jms     storez
                ld      R4
                jcn     nz,div_rr_one
div_r_one:      ldm     1
                jun     div_r_set

div_rr_one:     fim     P3,1
                jun     div_rr_set

;------------------------------------------------------------------------------
; Divide by an 8 bit value in R4,R5:   [DST] = [DST] / R4,R5
;------------------------------------------------------------------------------
div_x:          ld      R4
                jcn     z,div_r

;------------------------------------------------------------------------------
; Divide by an 8 bit value in R4,R5:   [DST] = [DST] / R4,R5
;------------------------------------------------------------------------------
div_rr:         fim     P3,0           ; clear number
div_rr_set:     fim     P4,0
div_rr_dloop:   xch     R1             ; data loop
                dac
                xch     R1
                src     P0
                rdm                    ; fetch next 4 bits into r7
                xch     R10
                ldm     0CH            ; 4 bit counter
                xch     R9
div_rr_bloop:   clc                    ; bit loop
                xch     R10
                ral                    ; rotate reg6 - reg7 - regA left by one bit
                xch     R10
                xch     R7
                ral
                xch     R7
                xch     R6
                ral
                xch     R6
                jcn     c,div_rr_sub
                xch     R7             ; try to sub the number
                sub     R5
                xch     R7
                cmc
                xch     R6
                sub     R4
                xch     R6
                jcn     c,div_rr_sub_ok
                xch     R7             ; add back the number
                add     R5
                xch     R7
                xch     R6
                add     R4
                xch     R6
                jun     div_rr_skip

div_rr_sub:     clc                    ; sub the number in case of carry
                xch     R7
                sub     R5
                xch     R7
                cmc
                xch     R6
                sub     R4
                xch     R6
div_rr_sub_ok:  inc     R10
div_rr_skip:    isz     R9,div_rr_bloop
                xch     R10
                wrm
                xch     R10
                isz     R8,div_rr_dloop
                bbl     0

;------------------------------------------------------------------------------
; calculate arc tg (1/n)
; R4,R5 : n
; R14,R15 : n*n (or n if n>127)
;------------------------------------------------------------------------------
arc_tg:         ldm     0
arc_tg_m:       xch     R11              
                jms     div_x_one      ; prepare 1/x
                fim     P6,1
                fim     P0,00H
                fim     P1,20H
                ld      R11
                rar
                jcn     c,atg_minus
                jms     add_xy
                jun     atg_loop
                
atg_minus:      jms     sub_xy
atg_loop:       clb                    ; next (2*k+1) 
                ldm     2
                add     R13
                xch     R13
                ldm     0
                add     R12
                xch     R12
                fim     P0,20H         ; REG2 = REG2 / n * n
                ld      R15
                xch     R5
                ld      R14
                xch     R4
                jms     div_x
                ld      R14
                ral
                jcn     nc,atg_skpdiv
                jms     div_x          ; in case of n>127 (n=239), another division is needed
atg_skpdiv:     fim     P0,10H         ; REG1 = REG2
                fim     P1,20H
                jms     mov_xy
                ld      R13            ; REG1 = REG1 / (2*k+1)
                xch     R5
                ld      R12
                xch     R4
                jms     div_x
atg_chk_loop:   src     P0             ; Check if REG1 is zero
                rdm
                jcn     nz,atg_nz
                isz     R1,atg_chk_loop
                bbl     0              ; return, if number is zero
                
atg_nz:         fim     P0,00H
                fim     P1,10H
                inc     R11            ; alternate add/sub functions
                ld      R11
                rar
                jcn     c,atg_sub
                jms     add_xy         ; REG0 = REG0 + REG1
                jun     atg_loop
atg_sub:        jms     sub_xy         ; REG0 = REG0 - REG1
                jun     atg_loop

                end
