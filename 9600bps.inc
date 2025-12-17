;==================================================================================================
; i4004 putchar and getchar functions for 9600 bps, 8 data bits, no parity, 1 stop bit
; (1/(5068000 MHz/7))*8 clocks/cycle = 11.05 µseconds/cycle
; for 9600 bps: 1000000 µseconds ÷ 9600 bits/second ÷ 11.05 µseconds/cycle = 9 cycles/bit
;==================================================================================================

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

;--------------------------------------------------------------------------------------------------
; 9600 bps N-8-1 serial function 'putchar'
; send the character in P1 to the console serial port (the least significant bit of port 0) 
; in addition to P1 (R2,R3) also uses P7 (R14,R15)
; preserves the character in P1.
;--------------------------------------------------------------------------------------------------
putchar:        fim P7,SERIALPORT
                src P7                  ; set port address
                ldm 16-5
                xch R14                 ; R14 is the counter for 5 bits (start bit plus bits 0-3)
                ld R3                   ; load bits 0-3 from R3
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

                ldm 16-5                ; R14 is the counter for 5 bits (bits 4-7 plus stop bit)
                xch R14
                ld R2                   ; load bits 4-7 from R2
                stc                     ; carry will eventually become the start bit
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
                
                               