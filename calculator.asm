            PAGE 0                      ; suppress page headings in ASW listing file
            cpu 4004                    ; Tell the Macro Assembler AS that this source is for the Intel 4004

;;;---------------------------------------------------------------------------
;;; calculator program for Intel 4004 single board computer
;;; adapted from 'calc.asm' by ryo mukai at https://github.com/ryomuk/test4004
;;; any changes I've made are purely cosmetic - Jim Loos
;;;
;;; Assemble with the Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;;;
;;; requires two 4002 RAM chips
;;;
;;; serial I/O at 9600 bps, N-8-1
;;;
;;; commands:
;;;     +       add          X = X + Y
;;;     -       subtract     X = X - Y
;;;     *       multiply     X = X * Y
;;;     /       divide       X = X / Y
;;;     r       square root  X = sqrt(X)
;;;     s       sign change  X = -X
;;;     c       clear registers
;;;     p       print X and Y registers
;;;     <ENTER> push register stack
;;;     q       quit
;;;---------------------------------------------------------------------------
;;; number expression (simple floating point)
;;;       1 11111
;;; char# 5 432109876543210
;;;  (+/-)D.DDDDDDDDDDDDDDD*(10^e)
;;; D0-15: fraction (D15=most significant digit, D0=least significant digit)
;;; D15 denotes an integer part, but it should be zero except while calculating addition or multiplication.
;;; it is used for avoiding overflow.
;;; the number is normalized so that D15 is zero and minimize exponent
;;; S0: exponent (0 to 14)
;;; S1: sign of the fraction (0=positive,15=negative)
;;; S2: error (0=no_error, 1=overflow, 2=divide_by_zero)
;;;---------------------------------------------------------------------------

;;;---------------------------------------------------------------------------
;;; P0 - working for print
;;; P1 - working for print, getchar, putchar
;;; P2 -
;;; P3 -   
;;; P4 - register address and character index (mainly reg_X)
;;; P5 - register address and character index (mainly reg_Y)
;;; P6 - working for register operation
;;; P7 - working for register operation

;;; R6 bit 0 = automatic enter flag (0:disable 1:enable)
;;; R6 bit 1 = input full flag (0:not full 1:full)
;;; R6 bit 3 = decimal point flag(0:no dp 1:dp set)
;;; R7 = digit counter for key input
;;; reg_X is automatically cleared if R7 is 0 (first digit input)
;;;---------------------------------------------------------------------------
    
    include "bitfuncs.inc"  ; include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).
    include "reg4004.inc"   ; include 4004 register definitions.    
    
;;;---------------------------------------------------------------------------
;;; registers used in the calculator
;;;---------------------------------------------------------------------------
reg_X  equ 00H          ; reg_X
reg_Y  equ 10H          ; reg_Y
reg_Z  equ 20H          ; reg_Z
reg_T  equ 30H          ; reg_T

reg_M  equ 40H          ; reg_M (working register for multiplication and division)
reg_A  equ 50H          ; reg_A (working register for square root)
reg_B  equ 60H          ; reg_B (working register for square root)    
reg_C  equ 70H          ; reg_C

; error flags
reg_error_overflow  equ 1
reg_error_divbyzero equ 2    

SERIALPORT equ 00H              ; address of the serial port. the least significant bit of port 00 is used for serial output.
LEDPORT    equ 40H              ; Address of the port used to control the red LEDs. "1" turns the LEDs on.
GPIO       equ 80H              ; 4265 General Purpose I/O device address

    org 0000H
;;;---------------------------------------------------------------------------
;;; program start
;;;---------------------------------------------------------------------------
    nop                         ; "To avoid problems with power-on reset, the first instruction at
                                ; program address 0000 should always be an NOP." (don't know why)
    fim P0,SERIALPORT
    src P0
    ldm 1
    wmp                         ; set serial output high to indicate 'MARK'
                
    fim P0,LEDPORT
    src P0
    ldm 0
    wmp                         ; write data to RAM LED output port, set all 4 outputs low to turn off all four LEDs                                            
    
    fim P0,lo(str_openmsg)      
    jms print_str               ; display the opening message
    jms calc_clear              ; clear registers

calc_start:
    ld R6
    rar
    ldm 0
    ral
    xch R6                      ; reset flags except for automatic enter flag
    clb
    xch R7                      ; set digit counter = 0
    fim P0,reg_X
    jms print_register_P0       ; print reg_X
    jms print_CRLF
    
; loop for inputing digits into reg_X    
calc_loop:                      
    jms getchar                 ; get input

    fim P0,'\r'                 ; 'ENTER' key?
    jms compare_P0_P1
    jcn zn,calc_loop1            
    jms print_CRLF
    jms calc_enter
    jun calc_start
    
calc_loop1:
    fim P0,'q'                  ; quit?
    jms compare_P0_P1
    jcn zn,calc_loop2
    jms print_CRLF
    fim P0,lo(str_bye)
    jms print_str               ; print "Bye!"    
    jun $                       ; jump here forever
    
calc_loop2:    
    fim P0,'+'                  ; add?
    jms compare_P0_P1
    jcn zn,calc_loop3
    jms putchar                 ; echo '+'
    jms print_CRLF
    jms calc_add
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop3:
    fim P0,'-'                  ; subtract?
    jms compare_P0_P1
    jcn zn,calc_loop4
    jms putchar                 ; echo '-'
    jms print_CRLF
    jms calc_sub
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop4:
    fim P0,'*'                  ; multiply?
    jms compare_P0_P1
    jcn zn,calc_loop5
    jms putchar                 ; echo '*'
    jms print_CRLF
    jms calc_mul
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop5:
    fim P0,'/'                  ; divide?
    jms compare_P0_P1
    jcn zn,calc_loop6
    jms putchar                 ; echo '/'
    jms print_CRLF
    jms calc_div
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop6:
    fim P0,'c'                  ; clear registers?
    jms compare_P0_P1
    jcn zn,calc_loop7
    jms print_CRLF
    jms calc_clear
    jun calc_start
    
calc_loop7:
    fim P0,'s'                  ; sign change?
    jms compare_P0_P1
    jcn zn,calc_loop8
    jms change_sign_reg_X
    jms print_CRLF
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop8:
    fim P0,'p'                  ; print registers?
    jms compare_P0_P1
    jcn zn,calc_loop9
    jms print_CRLF
    jun calc_print              ; 'calc_print' cannot be a subroutine because of the stack limitations
calc_print_return: 
    jun calc_start    
    
calc_loop9:
    fim P0,'r'                  ; square root?
    jms compare_P0_P1
    jcn zn,calc_loop10
    jun calc_squareroot         ; 'calc_squareroot' cannot be a subroutine because of the stack limitations
calc_sqr_return:    
    jms calc_set_auto_enter_flag
    jun calc_start
    
calc_loop10:
    ld R6                       ; check number full flag (R6.1)
    rar                         ; no more '0-9' or '.' input
    rar
    jcn c,calc_loop12
    fim P0,'.'                  ; '.' decimal point?
    jms compare_P0_P1
    jcn zn,calc_loop11
    ld R6
    ral
    jcn c,calc_loop12           ; skip if decimal point flag (R6.3) is already set
    jms putchar                 ; echo '.'
    jms calc_auto_push_and_clear
    jms calc_decimalpoint
    jun calc_loop
    
calc_loop11:
    jms isnum_P1
    jcn z,calc_loop12           ; skip if not a number
    jms putchar                 ; echo '.'
    jms calc_auto_push_and_clear
    jms calc_num
calc_loop12:
    jun calc_loop               ; go back for more input

;;;---------------------------------------------------------------------------
;;; check P1 '0' to '9' as an ASCII character
;;; return: acc=0 if P1 is not a number
;;;         acc=1 if P1 is a number
;;; destroys: P0
;;;---------------------------------------------------------------------------
isnum_P1:
    fim P0,'0'-1
    jms compare_P0_P1
    jcn c,isnum_false           ; '0'-1 >= P1
    fim P0,'9'
    jms compare_P0_P1
    jcn cn,isnum_false          ; '9' < P1
    bbl 1                       ; P1 is a number
isnum_false:
    bbl 0                       ; P1 is not a number
    
;;;---------------------------------------------------------------------------
;;;  set automatic enter flag
;;;---------------------------------------------------------------------------
calc_set_auto_enter_flag:  
    ld R6
    rar
    stc
    ral
    xch R6
    bbl 0

;;;---------------------------------------------------------------------------
;;; clear automatic enter flag
;;;---------------------------------------------------------------------------
calc_clear_auto_enter_flag:
    ld R6
    rar
    clc
    ral
    xch R6
    bbl 0

;;;---------------------------------------------------------------------------
;;; push reg_X and clear for the first '0-9' or '.' after operation
;;;---------------------------------------------------------------------------
calc_auto_push_and_clear:
    ld R6                       ; check automatic enter flag (R6.bit0)
    rar
    jcn cn,calc_push_l0
    jms calc_enter              ; push enter key

calc_push_l0:
    ld R7                       ; check digit count
    jcn zn,calc_push_exit       ; if R7 = 0 then R7++ and clear reg_X
    inc R7
    fim P0,reg_X
    jms clear_register_P0       ; clear x for the first keyin
calc_push_exit
    bbl 0

    org 0100H
;;;---------------------------------------------------------------------------
;;; set a decimal point
;;;---------------------------------------------------------------------------
calc_decimalpoint:
    ld R6
    ral
    stc                         ; set decimal point flag R6.bit3
    rar
    xch R6                  
    bbl 0

;;;---------------------------------------------------------------------------
;;; clear all registers
;;;---------------------------------------------------------------------------
calc_clear:
    fim P0,reg_X
    jms clear_register_P0
    fim P0,reg_Y
    jms clear_register_P0
    fim P0,reg_Z
    jms clear_register_P0
    fim P0,reg_T
    jms clear_register_P0
    jun calc_clear_auto_enter_flag ; clear flag and return
    
;;;---------------------------------------------------------------------------
;;; push register stack
;;;     X => Y => Z => T
;;;---------------------------------------------------------------------------
calc_enter:
    fim P6,reg_T
    fim P7,reg_Z
    jms ld_register_P6_P7   ; load register *P6 from register *P7 (reg_T <= reg_Z)
    fim P6,reg_Z
    fim P7,reg_Y
    jms ld_register_P6_P7   ; load register *P6 from register *P7 (reg_Z <= reg_Y)
    fim P6,reg_Y
    fim P7,reg_X
    jms ld_register_P6_P7   ; load register *P6 from register *P7 (reg_Y <= reg_X)
    jun calc_clear_auto_enter_flag ; clear flag and return
    
;;;---------------------------------------------------------------------------
;;; enter a number into X
;;; input: P1=('0',...'9') ASCII character
;;;        R7=digit count
;;;---------------------------------------------------------------------------
calc_num:
    jms ctoi_P1
    ld R3
    fim P7,reg_X
    ldm 15
    clc
    sub R7          
    xch R15                     ; P7=(reg_X).(#char=15-R7)
    src P7

    ld R6
    ral                         ; check R6.bit3 (decimal point flag)
    jcn c,calc_setnum           ; if decimal point flag is true, exponent is not updated set exponent of X
    ld R7
    wr0
calc_setnum:
    ld R3
    wrm
    inc R7
    ldm 15                      ; maximum number of digits is 14
    clc                         ; so set digit full flag when R7 becomes 15
    sub R7
    jcn zn,calc_num_exit
    ;; set digit full flag R6.bit1
    ld R6
    rar
    rar
    stc
    ral
    ral
    xch R6
calc_num_exit:
    bbl 0

;;;---------------------------------------------------------------------------
;;; X = X+Y
;;;---------------------------------------------------------------------------
calc_add:
    jms align_register_xy
    fim P6,reg_X
    fim P7,reg_Y
    src P6                      ; check sign of reg_X and reg_Y same or not
    rd1
    xch R0                      ; R0 = sign of X
    src P7
    rd1
    clc
    sub R0
    jcn z,calc_add_samesign
    jms cmp_fraction_P6_P7
    jcn z,calc_add_zero_exit
    jcn c,cmd_sub_x_y           ; P6 > P7
cmd_sub_y_x:
    fim P6,reg_M
    fim P7,reg_X
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_M <= reg_X)
    fim P6,reg_X
    fim P7,reg_Y
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_X <= reg_Y)
    fim P6,reg_Y
    fim P7,reg_M
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_Y <= reg_M)
cmd_sub_x_y:    
    fim P6,reg_X
    fim P7,reg_Y
    jms sub_fraction_P6_P7
    jun calc_add_exit

calc_add_samesign:
    fim P6,reg_X
    fim P7,reg_Y
    jms add_fraction_P6_P7
calc_add_exit:
    jun calc_normalize_and_pop

calc_add_zero_exit:
    fim P0,reg_X
    jms clear_register_P0
    jun calc_add_exit

;;;---------------------------------------------------------------------------
;;; common routine for finish calculation
;;; normalize reg_X
;;; pop registers
;;; reg_Y <= reg_Z <= reg_T
;;;---------------------------------------------------------------------------
calc_normalize_and_pop:
    fim P0,reg_X
    jms normalize_register_P0
    fim P6,reg_Y
    fim P7,reg_Z
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_Y <= reg_Z)
    fim P6,reg_Z
    fim P7,reg_T
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_Z <= reg_T)
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; add fraction of two registers
;;; reg(P6) = reg(P6) + reg(P7)
;;; register should be normalized so that d15 = 0
;;; in order to avoid overflow
;;; destroy: R13,R15,(R12 and R14 are not affected)
;;;---------------------------------------------------------------------------
add_fraction_P6_P7:
    clb
    xch R13
    clb
    xch R15
    clb
add_fra_loop:
    src P7
    rdm
    src P6
    adm
    daa
    wrm
    inc R13
    isz R15,add_fra_loop
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; subtract fraction
;;; reg(P6) = reg(P6) - reg(P7)
;;; reg(P6) should be equal or larger than reg(P7)
;;; in order to avoid underflow
;;; destroy: R13,R15,(R12 and R14 are not affected)
;;;---------------------------------------------------------------------------
;;; reference
;;; "Intel MCS-4 Assembly Language Programming Manual" DEC 1973,
;;; 4.8 Decimal Subtraction, pp.4-20--23
;;;---------------------------------------------------------------------------
sub_fraction_P6_P7:
    clb
    xch R13
    clb
    xch R15
    clb
    stc
sub_fra_loop:
    tcs
    src P7
    sbm
    clc
    src P6
    adm
    daa
    wrm
    inc R13
    isz R15,sub_fra_loop
    bbl 0

;;;---------------------------------------------------------------------------
;;; compare fraction of reg(P6) and reg(P7)
;;; output: acc=1,cy=0 if reg(P6) < reg(P7)
;;;         acc=0,cy=1 if reg(P6)== reg(P7)
;;;         acc=1,cy=1 if reg(P6) > reg(P7)
;;; reg(P6) - (P7) (the carry bit is a complement of the borrow)
;;; working: R0,R1
;;; destroy: P0,R13,R15,(R12 and R14 are not affected)
;;;---------------------------------------------------------------------------
cmp_fraction_P6_P7: 
    clb
    xch R0                      ; R0 = 0

cmp_fraction_loop:              ; for i(R0)=0 to 15
    ld R0
    cma
    xch R13
    src P6
    rdm
    xch R1                      ; R1=reg(P6)[15-i]

    ld R0
    cma
    xch R15
    src P7

    ld R1
    clc
    sbm                         ; acc=reg(P6)[15-i] - reg(P7)[15-i]

    jcn z,cmp_fraction_next
    jcn c,cmp_fraction_exit11
    jun cmp_fraction_exit10

cmp_fraction_next:
    isz R0,cmp_fraction_loop
    bbl 0                       ; reg(P6) == reg(P7)

cmp_fraction_exit10:
    bbl 1                       ; reg(P6) < reg(P7)

cmp_fraction_exit11:
    bbl 1                       ; reg(P6) > reg(P7)

;;;---------------------------------------------------------------------------
;;; minimize exponent
;;; example
;;; 0.0000001 e 9 ->shift l7->  1.0000000 e 2 -> shift R1 -> 0.10000000 e3
;;; 0.0000001 e 7 ->shift l7->  1.0000000 e 0 -> shift R1 -> 0.10000000 e1
;;; 0.0000001 e 5 ->shift l5->  0.0100000 e 0
;;; 
;;; working: P0,R2,R3
;;;---------------------------------------------------------------------------
normalize_register_P0:  
    src P0
    rd0                         ; exponent of reg(P0)
    cma
    xch R3                      ; R3 = 15 - exponent
    
    clb
    xch R2                      ; R2=0 (counter)
    jun nm_loop_entry
nm_loop:
    ld R2
    cma
    xch R1                      ; R1=15,14,..,0
    src P0
    rdm
    jcn zn,nm_go_shift
    inc R2
nm_loop_entry:
    isz R3,nm_loop
nm_go_shift:
    ;  exponent = exponent - shift count
    rd0
    clc
    sub R2
    wr0
    ld R2                       ; acc = shift count
    jms shift_fraction_left_P0_acc

    ldm 15                      ; check most significant digit
    xch R1                      ; and shift to right if it is not zero
    src P0
    rdm
    jcn z,nm_exit
    rd0                         ; increment exponent
    iac
    wr0
    jcn cn,nm_noerror
    ldm reg_error_overflow
    wr2 ;; set overflow flag
nm_noerror:
    ldm 1
nm_exit:
    jun shift_fraction_right_P0_acc

    org 0200H
;;;---------------------------------------------------------------------------
;;; X = X*Y
;;;---------------------------------------------------------------------------
calc_mul:
    fim P0,reg_X
    jms iszero_register_P0
    jcn zn,calc_mul_zero

    fim P0,reg_Y
    jms iszero_register_P0
    jcn zn,calc_mul_zero
    
    fim P6,reg_X
    fim P7,reg_Y

    jms get_sign_product_P6_P7
    src P6
    wr1
    
    ;;  calculate exponent of the result
    rd0
    xch R0
    src P7
    rd0
    clc
    add R0
    src P6
    wr0                         ; set exp x (tentative) it may be adjusted by the normalization
    jcn cn,calc_mul_l0          ; check overflow
    ldm reg_error_overflow
    wr2                         ; set overflow flag
calc_mul_l0:
    jms mul_fraction_xy

calc_mul_exit:
    jun calc_normalize_and_pop
calc_mul_zero:
    fim P0,reg_X
    jms clear_register_P0
    jun calc_mul_exit

;;;---------------------------------------------------------------------------
;;; multiply fraction of reg_X and reg_Y
;;; reg_X = reg_X * reg_Y
;;; working: P6,P7,P5,P0(for shift),P1(for shift),P4(R8,R9)
;;;---------------------------------------------------------------------------
;;; D15=0 (number is normalized)
;;; sum up followings and store to fra_x
;;; fra_y
;;; 0EDCBA9876543210 * 0 fra_m(=fra_x)
;;;  0EDCBA987654321 * e
;;;   0EDCBA98765432 * d
;;;    0EDCBA9876543 * c
;;;     0EDCBA987654 * b
;;;      0EDCBA98765 * a
;;;       0EDCBA9876 * 9
;;;        0EDCBA987 * 8
;;;         0EDCBA98 * 7
;;;          0EDCBA9 * 6
;;;           0EDCBA * 5
;;;            0EDCB * 4
;;;             0EDC * 3
;;;              0ED * 2
;;;               0E * 1
;;;                0 * 0
;;;---------------------------------------------------------------------------
mul_fraction_xy:
    fim P6,reg_M
    fim P7,reg_X
    jms ld_fraction_P6_P7       ; fra_m <= fra_x

    fim P0,reg_X
    jms clear_fraction_P0       ; fra_x = 0,status(sign,exp) is reserved
    
    fim P5,reg_M                ; for mult loop (copy of x)
    fim P6,reg_X                ; for add (total)
    fim P7,reg_Y                ; for add
    fim P0,reg_Y                ; for shift (working reg. P1)

    clb
    xch R8
mul_loop:                       ; for i(R8)=0 to 15
    ld R8
    cma
    xch R11                     ; R11 = 15,14,...,0
    src P5
    rdm
    jcn z,mul_loop_next         ; next if (reg_Y)[15-i] == 0
    cma
    iac
    xch R9                      ; R9 = 16-(reg_Y)[15-i]
mul_add_loop:                   ; add fra_m to fra_x '(reg_Y)[15-i] times'
    jms add_fraction_P6_P7
    isz R9,mul_add_loop
mul_loop_next:
    ldm 1
    fim P0,reg_Y
    jms shift_fraction_right_P0_acc ; shift fra_y 1 digit right
    isz R8,mul_loop

    bbl 0
    
;;;---------------------------------------------------------------------------
;;; X = Y-X
;;;---------------------------------------------------------------------------
calc_sub:
    jms change_sign_reg_X
    jun calc_add
    
;;;---------------------------------------------------------------------------
;;; shift fraction of the register to right with filling zeros
;;; input: P0(=D3D2D1D0.XXXX (D3D2=#chip,D1D0=#reg)
;;;        acc=shift count
;;; working: P0(R0,R1),P1(R2,R3)
;;; destroy P1(R2,R3),R1 becomes 0 but R0 is not affected
;;;---------------------------------------------------------------------------
shift_fraction_right_P0_acc:
    jcn z,shiftr_exit  ; exit if acc==0
    xch R3                      ; R3 = acc = shift
    ld R0
    xch R2                      ; R2 = R0

    clb                         ; clear acc and cy
    xch R1                      ; R1=0
shiftr_loop:                    ; for(i=0 to 15) P0(reg(i))=P1(reg(i+shift))
    ldm 0
    jcn c,shiftr_write
shiftr_read:    
    src P1
    rdm
shiftr_write:
    src P0
    wrm
    inc R3
    ld R3
    jcn zn,shiftr_next          ; check if shift completed
    stc                         ; set flag to fill remaining bits with 0 
shiftr_next:
    isz R1,shiftr_loop
shiftr_exit:
    bbl 0

;;;---------------------------------------------------------------------------
;;; shift fraction of the register to left with filling zeros
;;; input: P0(=D3D2D1D0.XXXX (D3D2=#chip,D1D0=#reg)
;;;        acc=shift count
;;; working: P0(R0,R1),P1(R2,R3),P2(R4,R5),R15
;;; destroy P1(R2,R3),P2,R15,R1 becomes 0 but R0 is not affected
;;;---------------------------------------------------------------------------
shift_fraction_left_P0_acc:
    jcn z,shiftl_exit           ; exit if acc==0
    xch R5                      ; R5 = acc = shift
    ld R0
    xch R2                      ; R2 = R0

    clb                         ; clear acc and cy
    xch R4                      ; R4=0 (R4=i,R5=i+shift)
shiftl_loop:                    ; for(i=0 to 15) P0(reg(~i))=P1(reg(~(i+shift))
    ldm 0
    xch R15
    jcn c,shiftl_write
shiftl_read:    
    ld R5
    cma
    xch R3                      ; R3 = ~R5 =~(i+shift)
    src P1
    rdm
    xch R15
shiftl_write:
    ld R4
    cma
    xch R1                       ; R1 = ~R4 =~i
    src P0
    xch R15
    wrm
    inc R5
    ld R5
    jcn zn,shiftl_next          ; check if shift completed
    stc                         ; set flag to fill remaining bits with 0 
shiftl_next:
    isz R4,shiftl_loop
shiftl_exit:
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; align decimal point to larger register
;;; input: P6(=D3D2D1D0.0000 (D3D2=#chip,D1D0=#reg)
;;;        P7(=D3D2D1D0.0000 (D3D2=#chip,D1D0=#reg)
;;; working: R10,R11
;;;---------------------------------------------------------------------------
align_register_xy:
    fim P6,reg_X
    fim P7,reg_Y
    src P6
    rd0
    xch R10                     ; R10 = expoenent of reg_P6
    src P7
    rd0 
    xch R11                     ; R11 = expoenent of reg_P7

    ld R11
    clc
    sub R10
    jcn c,ey_ge_ex ; R11 >= R10
    ;; R11 < R10
    cma
    iac
    fim P0,reg_Y
    jms shift_fraction_right_P0_acc
    ld R10
    src P7
    wr0
    jun align_exit
ey_ge_ex:
    fim P0,reg_X
    jms shift_fraction_right_P0_acc
    ld R11
    src P6
    wr0
align_exit:
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; clear register
;;; input: P7(=D3D2D1D0.0000 (D3D2=chip number, D1D0=register number))
;;; output: acc=0,R1=0,(R0 is not affected)
;;;---------------------------------------------------------------------------
clear_register_P0:
    clb
    src P0
    wr0
    wr1
    wr2
    wr3
    
;;;---------------------------------------------------------------------------
;;; clear_fraction_P0
;;;---------------------------------------------------------------------------
clear_fraction_P0:
    clb
clear_register_l0:
    src P0
    wrm
    isz R1,clear_register_l0
    bbl 0

;;;---------------------------------------------------------------------------
;;; load register *P6 from register *P7 (*P6 <= *P7)
;;; input: P6(D3D2D1D0.0000 (D3D2=chip number, D1D0=register number) 
;;;        P7(D3D2D1D0.0000 (D3D2=chip number, D1D0=register number))
;;; output: acc=0, R13=0, R15=0
;;; destroy R13,R15 (R12 and R14 are not affected)
;;;---------------------------------------------------------------------------
ld_register_P6_P7:
    ;; copy status characters
    src P7
    rd0
    src P6
    wr0

    src P7
    rd1
    src P6
    wr1

    src P7
    rd2
    src P6
    wr2

    src P7
    rd3
    src P6
    wr3
    
;;;---------------------------------------------------------------------------
;;; ld_fraction_P6_P7
;;;---------------------------------------------------------------------------
ld_fraction_P6_P7
    ; clb
    ; xch R13                   ; clear R13
    ; clb
    ; xch R15                   ; clear R15
ld_fraction_l0:
    src P7
    rdm                         ; read a digit from the source register
    src P6
    wrm                         ; write the digit to memory
    inc R13
    isz R15,ld_fraction_l0
    bbl 0

;;;---------------------------------------------------------------------------
;;; check if reg(P0) == 0 or not
;;; return: acc = (reg==0) ? 1 : 0;
;;; destroy: R1 (R0 is not affected)
;;;---------------------------------------------------------------------------
iszero_register_P0:
    clb
    xch R1
iszero_loop:
    src P0
    rdm
    jcn zn,iszero_exit0
    isz R1,iszero_loop

    bbl 1
iszero_exit0:
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; X = -X
;;; destroy: P7
;;;---------------------------------------------------------------------------
change_sign_reg_X:
    fim P7,reg_X
    src P7
    rd1
    cma
    wr1
    bbl 0

    org 0300H
;;;---------------------------------------------------------------------------
;;; X = Y / X
;;;---------------------------------------------------------------------------
calc_div:
    fim P0,reg_X
    jms normalize_register_P0
    jms iszero_register_P0
    jcn zn,calc_div_by_zero

    fim P0,reg_Y
    jms iszero_register_P0
    jcn zn,calc_dividend_zero
    
    fim P6,reg_X
    fim P7,reg_Y

    jms get_sign_product_P6_P7
    src P7
    wr1                         ; save sign to y
    
    ;; if devisor(reg_X) is less than 0.1,
    ;; shift it left until it become equal or larger than 0.1
    ;; and increment the exponent of devidend
    ;; example
    ;; x=0.0001 -> x=0.1000,exponent of y += 3
    src P6
    rd0                         ; check exponent of reg_X(devisor)
    jcn zn,div_frac_adj_exp
div_loop_d14:
    ;; increment exponent of y
    src P7                      ; y
    rd0
    iac
    wr0                         ; exp(y)++
    jcn nc,div_loop_l0
    ldm reg_error_overflow
    wr2                         ; set overflow flag,but continue calculation
div_loop_l0:
    ldm 14
    xch R13
    src P6                      ; x
    rdm                         ; acc = d14 of x
    jcn zn,div_frac             ; exit loop and continue calculation
    ldm 1
    jms shift_fraction_left_P0_acc
    jun div_loop_d14

    ; adjust exponent of y
div_frac_adj_exp:
    src P6                      ; x
    rd0
    dac
    xch R0                      ; R0 = (exponent of x)-1
    src P7
    rd0
    clc
    sub R0                      ; exp(y) - exp(x)
    wr0
    jcn c,div_frac              ; no borrow
    cma
    iac
    fim P0,reg_Y
    jms shift_fraction_right_P0_acc ; shift frac(y) and set exp(y)=0
    clb
    wr0
div_frac:
    jms div_fraction_xy
    jun calc_normalize_and_pop
    
calc_div_by_zero:
    fim P0,reg_X
    src P0
    ldm reg_error_divbyzero
    wr2         ; set error flag
    bbl 0
calc_dividend_zero:
    fim P0,reg_X
    jms clear_register_P0
    bbl 0
    
;;;---------------------------------------------------------------------------
;;; frac(X) = frac(Y) / frac(X)
;;; working: P6,P7,P5,P0(for shift),P1 (for shift),P4(R8,R9)
;;;---------------------------------------------------------------------------
;;;  compare and subtract and count,and shift
;;; 
;;;  0EDCBA9876543210
;;;  0EDCBA9876543210 -> e
;;;
;;;  0EDCBA9876543210
;;;   0EDCBA987654321 -> d
;;; 
;;;  0EDCBA9876543210
;;;    0EDCBA98765432 -> c
;;; ...
;;;  0EDCBA9876543210 -> 0
;;;                0E
;;;
;;; e!=0
;;;---------------------------------------------------------------------------
div_fraction_xy:
    fim P6,reg_Y
    fim P7,reg_X
    fim P5,reg_M

    fim P0,reg_M
    jms clear_fraction_P0

    ldm 1
    xch R8                      ; for i(R8)= 1 to 15;
div_loop:   
    clb
    xch R9                      ; counter R9 = 0
div_sub_count:
    jms cmp_fraction_P6_P7      ; compare Y with X
    jcn cn,div_sub_count_exit   ; jump if reg_Y < reg_X

    ;; check R9 is already 9
    ;; it occurs when shifted divisor is truncated
    ;; (ex. previous loop 100/109 -> this loop 100/10)
    ldm 9
    clc
    sub R9
    jcn z,div_sub_count_exit
    
    jms sub_fraction_P6_P7      ; Y = Y - X
    inc R9
    jun div_sub_count
div_sub_count_exit: 
    ld R8
    cma
    xch R11                     ; R11 = 14,13,...,0
    src P5                      ; reg_M
    ld R9
    wrm                         ; reg_M(R11) = R9
    ldm 1
    fim P0,reg_X
    jms shift_fraction_right_P0_acc ; X=X/10

    isz R8,div_loop

    fim P6,reg_X
    fim P7,reg_Y
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_A <= reg_X)
    fim P7,reg_M
    jms ld_fraction_P6_P7       ; copy fraction of M to X
                                ; X need to be normalized
    bbl 0
    ;;  jun return_div_fraction_xy

;;;---------------------------------------------------------------------------
;;; calculate sign of the result for multiplication and division
;;; result: acc=0 (+) if reg(P6) and reg(P7) have the same sign (++or--)
;;;            =15(-) if reg(P6) and reg(P7) have the different signs (+-or-+)
;;; destroy: R0
;;;---------------------------------------------------------------------------
get_sign_product_P6_P7: 
    ;;  calculate sign of the result for multiplication and division
    src P6                      ; check sign of reg_X and reg_Y same or not
    rd1
    xch R0                      ; R0 = sign of X
    src P7
    rd1                         ; sign of Y
    clc
    sub R0
    jcn z,get_sign_exit
    bbl 15                      ; negative sign
get_sign_exit:
    bbl 0

;;;---------------------------------------------------------------------------
;;; print the contents of the number register
;;; input: P0(R0=D3D2D1D0 (D3D2=chip number, D1D0=register number))
;;; destroy P6,P7,P5(R10,R11),P1
;;; output: acc=0
;;;---------------------------------------------------------------------------
print_register_P0:
    src P0
    rd2
    jcn z,print_register_equ_err
    fim P1,'e'
    jms putchar
print_register_equ_err
    fim P1,'+'
    src P0
    rd1
    jcn z,print_register_sgn
    fim P1,'-'
print_register_sgn:
    jms putchar
    src P0
    rd0         
    xch R10                     ; load R10=exponent

    ;; print first digit(d15) if it is not zero
    ;; (it should be '0' if the number is normalized) 
    ldm 15
    xch R1
    src P0
    rdm
    jcn z,print_check_exp
    jms print_acc

print_check_exp:                ; print decimal point if exponent is 0
    ld R10
    jcn zn,print_register_loop_setup
    fim P1,'.'
    jms putchar

print_register_loop_setup:
    clb
    ldm 1
    xch R11                     ; R11 is loop counter start from 1
print_register_loop:
    ldm 15
    clc
    sub R11                     ; (R11 =  1,2,...,15) 
    jcn z,print_exit            ; skip last digit
    xch R1                      ; ( R1 = 14,13,...,1)
    src P0
    rdm
    jms print_acc

    clb                         ; print decimal point
    ld R10
    sub R11
    jcn zn,print_register_l1
    fim P1,'.'
    jms putchar
print_register_l1:
    isz R11,print_register_loop
print_exit: 
    bbl 0
 
;;;---------------------------------------------------------------------------
;;; compare P0 to P1
;;; input: P0, P1
;;; output: acc=1, cy=0 if P0<P1
;;;         acc=0, cy=1 if P0==P1 
;;;         acc=1, cy=1 if P0>P1
;;; P0 - P1 (the carry bit is a complement of the borrow)
;;;---------------------------------------------------------------------------
compare_P0_P1:
    clb
    ld R0           
    sub R2                      ;R0-R2
    jcn z,cmp_l1
    jcn c,cmp_exit11
    bbl 1                       ;P0<P1, acc=1, cy=0
cmp_l1: 
    clb
    ld R1
    sub R3                      ;R1-R3
    jcn z,cmp_exit01
    jcn c,cmp_exit11
    bbl 1                       ;P0<P1, acc=1, cy=0
cmp_exit01:
    bbl 0                       ;P0==P1,acc=0, cy=1
cmp_exit11
    bbl 1                       ;P0>P1, acc=1, cy=1
    
;;;---------------------------------------------------------------------------
;;; convert character ('0'...'F') to value 0000 ... 1111
;;; input: P1(R2R3)
;;; output: R3,(R2=0)
;;;---------------------------------------------------------------------------
ctoi_P1:
    clb
    ldm 3
    sub R2
    jcn z,ctoi_09               ; check upper 4bit
    clb
    ldm 9
    add R3
    xch R3                      ; R3 = R3 + 9 for 'a-fa-f'
ctoi_09:
    clb
    xch R2                      ; R2 = 0
    bbl 0

    org 0400H    
;;;---------------------------------------------------------------------------
;;; X = sqrt(X)
;;; registers Y,Z,T are destroyed
;;; this function cannot be a subroutine because of stack limitations
;;;---------------------------------------------------------------------------
calc_squareroot:
    fim P0,lo(str_calc_sqrt)
    jms print_str               ; print "SQR "
    fim P0,reg_T
    jms clear_register_P0
    ldm 14
    xch R1
    src P0
    ldm 5
    wrm                         ; reg_T = 0.5
    fim P6,reg_A
    fim P7,reg_X
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_A <= reg_X)
    fim P3,0C0H                 ; set a limit of 64 times (16*4) through the 'calc_sqr_loop' loop below

; loop of "0.5 enter X enter A enter X / + *"
; reg_T keeps 0.5 
calc_sqr_loop:  
    fim P6,reg_Z
    fim P7,reg_X
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_Z <= reg_X)

    fim P6,reg_B
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_B <= reg_X)

    fim P6,reg_Y
    fim P7,reg_A
    jms ld_register_P6_P7       ; load register *P6 from register *P7 (reg_Y <= reg_A)

    jms calc_div
    jms calc_add
    jms calc_mul

    ;fim P0,reg_X
    ;jms print_register_P0
    ;jms print_CRLF
    fim P1,'.'
    jms putchar    

    fim P6,reg_B
    fim P7,reg_X
    jms cmp_fraction_P6_P7
    jcn z,calc_sqr_exit
    
    isz R7,calc_sqr_loop
    isz R6,calc_sqr_loop
    
calc_sqr_exit:
    jms print_CRLF
    jun calc_sqr_return
    
;;;---------------------------------------------------------------------------
;;; print all registers
;;;---------------------------------------------------------------------------
calc_print:
    fim P0,lo(str_reg_X)
    jms print_str
    fim P0,reg_X
    jms print_register_P0
    jms print_CRLF

    fim P0,lo(str_reg_Y)
    jms print_str
    fim P0,reg_Y
    jms print_register_P0
    jms print_CRLF
    
    ;fim P0,lo(str_reg_Z)
    ;jms print_str
    ;fim P0,reg_Z
    ;jms print_register_P0
    ;jms print_CRLF
    
    ;fim P0,lo(str_reg_T)
    ;jms print_str
    ;fim P0,reg_T
    ;jms print_register_P0
    ;jms print_CRLF
    
    ;fim P0,lo(str_reg_M)
    ;jms print_str
    ;fim P0,reg_M
    ;jms print_register_P0
    ;jms print_CRLF

    ;fim P0,lo(str_reg_A)
    ;jms print_str
    ;fim P0,reg_A
    ;jms print_register_P0
    ;jms print_CRLF

    ;fim P0,lo(str_reg_B)
    ;jms print_str
    ;fim P0,reg_B
    ;jms print_register_P0
    ;jms print_CRLF

    ;fim P0,lo(str_reg_C)
    ;jms print_str
    ;fim P0,reg_C
    ;jms print_register_P0
    jms print_CRLF    
    jms print_CRLF
    jun calc_print_return
    
;--------------------------------------------------------------------------------------------------
; 9600bps, N-8-1 serial output function.
; sends the character in P1 to the serial port. the character in
; P1 is preserved. in addition to P1,uses P6 and P7.
;--------------------------------------------------------------------------------------------------    
putchar:    fim P7,SERIALPORT
            src P7              ; set port address
            ldm 16-5
            xch R13
            ld R3
            clc                 ; clear carry to make the start bit 0
            ral    
; send 5 bits; the start bit and bits 0-3. each bit takes 9 cycles
putchar1:   nop
            nop
            nop
            nop
            nop
            wmp
            rar
            isz R13,putchar1

            fim P6,16-5
            ld R2
            stc                 ; set carry to make the stop bit 1
            nop
            nop
; send 5 bits; bits 4-7 and the stop bit. each bit takes 10 cycles
putchar2:   wmp
            fim P7,16-2
            isz R15,$
            rar
            isz R13,putchar2
            bbl 0
            
;--------------------------------------------------------------------------------------------------
; 9600bps, N-8-1 serial input function.
; wait for a character from the serial port. returns the character 
; received from the serial port in P1. in addition to P1,uses P6 and P7.
;--------------------------------------------------------------------------------------------------                
getchar:    fim P6,16-4
            jcn t,$                 ; wait for start bit (test="1")
            fim P7,16-4
            isz R15,$               ; 12 cycles between start bit and bit 0.  phase(bit0)= 12 -9.645 = 2.355cycle
getchar1:   jcn tn,getchar2         ; check the recived bit
            stc                     ; if test input==0,then set carry
            jun getchar3
getchar2:   clc                     ; if test input==1,then clear carry
            nop
            nop
getchar3:   rar                     ; load cy->acc
            nop                     ; 9 cycles/bit (error=-0.645 cycle/bit)
            isz R13,getchar1        ; repeat until 4 bits received. phase(here)= 2.355 -0.645*3 = 0.42cycle
            xch R3               
            fim P6,16-4             ; loop for second (upper) 4 bits. 12 cycles between bit 3 and bit 4. phase(bit4)= 2.42 +12 -9.645 = 2.775 cycle
getchar4:   jcn tn,getchar5         ; check the input
            stc                     ; if test==0,then set carry
            jun getchar6           
getchar5:   clc                     ; if test==1,then clear carry
            nop                    
            nop                     
getchar6:   rar                     ; load cy->acc
            nop                     ; 9 cycles/bit (error=-0.645 cycle/bit)
            isz R13,getchar4        ; repeat until 4 bits received. phase(here)= 4.755 -0.645*3 = 0.84 cycle
            xch R2                  ; 10 cycles/between bit 7 and stopbit. phase(stop)= 2.84 +10 -9.645 = 1.195cycle 
            jcn tn,getchar7         ; check for the stop bit
            bbl 1                   ; return 1 to indicate stop bit not detected (timing error)
getchar7:   bbl 0                   ; return 0 to indicate stop bit detected (timing ok)
            
;;;---------------------------------------------------------------------------
;;; print contents of accumulator ('0'...'F') as a character
;;; destroy: P1,P6,P7,acc
;;;---------------------------------------------------------------------------
print_acc:
    fim R2R3,30H                ;'0'
    clc                         ; clear carry
    daa                         ; acc=acc+6 if acc>9 and set carry
    jcn cn,printacc_l1
    inc R2
    iac
printacc_l1:    
    xch R3                      ; R3<-acc
    jun putchar                 ; not jms but jun (jump to putchar and return)

;;;---------------------------------------------------------------------------
;;; print "\r\n"
;;; destroy: P1,acc
;;; this routine consumes 2 pc stack
;;;---------------------------------------------------------------------------
print_CRLF:
    fim P1,'\r'
    jms putchar
    fim P1,'\n'
    jun putchar

;;;---------------------------------------------------------------------------
;;; print "\r"
;;; destroy: P1,acc
;;; this routine consumes 1 pc stack
;;;---------------------------------------------------------------------------
print_CR:
    fim P1,'\r'
    jun putchar

;;;---------------------------------------------------------------------------
;;; print "\n"
;;; destroy: P1,acc
;;; this routine consumes 1 pc stack
;;;---------------------------------------------------------------------------
print_LF:
    fim P1,'\n'
    jun putchar

    org 0500H    
;;;----------------------------------------------------------------------------
;;; print the zero-terminated string whose first character's address is contained in P0
;;;----------------------------------------------------------------------------
print_str:      fin P1                  ; fetch the character pointed to by P0 into P1
                jms txtout              ; print the character, increment the pointer to the next character
                jcn zn,$-3              ; go back for the next character
                bbl 0
    
;-----------------------------------------------------------------------------------------
; This function is used by all the text string printing functions. If the character in P1 
; is zero indicating the end of the string, returns 0. Otherwise prints the character and 
; increments P0 to point to the next character in the string then returns 1.
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
                
;;;----------------------------------------------------------------------------
;;; string data
;;; the string data must be located in the same page as the print_str routine.
;;;----------------------------------------------------------------------------
str_openmsg:
    data "\r\n\n\nIntel 4004 SBC Calculator program assembled on ",DATE," at ",TIME,"\r\n\n",0
str_calc_sqrt:
    data " SQR ",0
str_reg_X:
    data "X ",0
str_reg_Y:
    data "Y ",0
str_reg_Z:
    data "Z ",0
str_reg_T:
    data "T ",0
str_reg_M:
    data "M ",0    
str_reg_A:
    data "A ",0
str_reg_B:
    data "B ",0
str_reg_C:
    data "C ",0    
str_bye:
    data "Bye!\r\n",0    
    
    end