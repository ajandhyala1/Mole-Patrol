RCC_AHB1ENR     EQU 0x40023830

; ---- GPIO Base Addresses ----
GPIOA_BASE      EQU 0x40020000
GPIOB_BASE      EQU 0x40020400
GPIOC_BASE      EQU 0x40020800

; ---- GPIO Register Offsets ----
MODER_OFFSET    EQU 0x00
IDR_OFFSET      EQU 0x10
ODR_OFFSET      EQU 0x14

; ---- RCC bits: enable GPIOA, GPIOB, GPIOC ----
RCC_ENABLE_ABC  EQU 0x07

; ---- Mole window delays ----
DELAY_EASY      EQU 0x60000
DELAY_HARD      EQU 0x24000

; ---- Outer 10-second game timer ----
GAME_TIME       EQU 13

; ---- LCD pin masks ----
; RS is now on GPIOB (PB5) - handled separately
; EN and data lines remain on GPIOA
LCD_RS_PIN      EQU (1 << 5)           ; PB5 - RS
LCD_EN          EQU (1 << 6)           ; PA6 - EN
LCD_D4          EQU (1 << 7)           ; PA7
LCD_D5          EQU (1 << 8)           ; PA8
LCD_D6          EQU (1 << 9)           ; PA9
LCD_D7          EQU (1 << 10)          ; PA10
LCD_DATA_MASK   EQU (LCD_D4 :OR: LCD_D5 :OR: LCD_D6 :OR: LCD_D7)
LCD_EN_MASK     EQU LCD_EN

; ---- Score / mode / round counter stored in RAM ----
                AREA mole_data, DATA, READWRITE
score           DCD 0
mode            DCD 0
rand_seed       DCD 0xACE1
rounds_left     DCD 0

; ---- String constants in ROM ----
                AREA mole_strings, DATA, READONLY
str_pick1       DCB "Pick Mode:", 0
str_pick2       DCB "B1=EASY B2=HARD", 0
str_score_lbl   DCB "Score: ", 0
str_timeup1     DCB "Time Up!", 0
str_win1        DCB "You Win!", 0
str_easy        DCB "Mode: Easy", 0
str_hard        DCB "Mode: Hard", 0

                AREA lab3, CODE, READONLY
                EXPORT __main

; __main - Entry Point
__main          PROC

                ; --- Enable clocks GPIOA, GPIOB, GPIOC ---
                LDR  R0, =RCC_AHB1ENR
                LDR  R1, [R0]
                ORR  R1, R1, #RCC_ENABLE_ABC
                STR  R1, [R0]

                ; --- Configure GPIOA ---
                ; PA0  = output (LED mole0)
                ; PA1  = output (LED mole1)
                ; PA4  = output (LED mole2)
                ; PA5  = input  (free - RS moved to PB5)
                ; PA6  = output (LCD EN)
                ; PA7  = output (LCD D4)
                ; PA8  = output (LCD D5)
                ; PA9  = output (LCD D6)
                ; PA10 = output (LCD D7)
                LDR  R0, =GPIOA_BASE
                LDR  R1, [R0, #MODER_OFFSET]
                MOVW R2, #0xFFFF
                MOVT R2, #0x003F            ; clear bits [21:0]
                BIC  R1, R1, R2
                ; PA0=01, PA1=01, PA4=01, PA6=01, PA7=01, PA8=01, PA9=01, PA10=01
                ; PA5 left as input (00)
                MOVW R2, #0x5445            ; lower 16: PA0,PA1,PA4,PA6,PA7
                MOVT R2, #0x0015            ; upper:    PA8,PA9,PA10
                ORR  R1, R1, R2
                STR  R1, [R0, #MODER_OFFSET]

                ; --- Configure GPIOB ---
                ; PB0 = output (LED mole3)
                ; PB3 = input  (button mole3)
                ; PB4 = input  (button mole4)
                ; PB5 = output (LCD RS)
                LDR  R0, =GPIOB_BASE
                LDR  R1, [R0, #MODER_OFFSET]
                MOVW R2, #0x0FFF            ; clear bits [11:0] PB0..PB5
                BIC  R1, R1, R2
                ORR  R1, R1, #0x001         ; PB0=output (bits 1:0 = 01)
                ORR  R1, R1, #0x400         ; PB5=output (bits 11:10 = 01)
                STR  R1, [R0, #MODER_OFFSET]

                ; --- Configure GPIOC ---
                ; PC0 = input  (button mole0 / easy)
                ; PC1 = output (LED mole4)
                ; PC2 = input  (button mole1 / hard)
                ; PC3 = input  (button mole2)
                LDR  R0, =GPIOC_BASE
                LDR  R1, [R0, #MODER_OFFSET]
                BIC  R1, R1, #0x000000FF
                ORR  R1, R1, #0x00000004    ; PC1=output
                STR  R1, [R0, #MODER_OFFSET]

                ; --- All LEDs off ---
                BL   leds_off

                ; --- Initialise LCD ---
                BL   lcd_init

                B    wait_mode
                LTORG

; wait_mode - Show mode-select screen, wait for PC0 or PC2
wait_mode
                BL   lcd_clear

                BL   lcd_line1
                LDR  R0, =str_pick1
                BL   lcd_print_string

                BL   lcd_line2
                LDR  R0, =str_pick2
                BL   lcd_print_string

wait_mode_poll
                LDR  R0, =GPIOC_BASE
                LDR  R1, [R0, #IDR_OFFSET]
                TST  R1, #(1 << 0)
                BNE  set_easy
                TST  R1, #(1 << 2)
                BNE  set_hard
                B    wait_mode_poll

set_easy
                LDR  R0, =mode
                MOV  R1, #0
                STR  R1, [R0]

                BL   lcd_clear
                BL   lcd_line1
                LDR  R0, =str_easy
                BL   lcd_print_string
                MOVW R0, #0x0000
                MOVT R0, #0x0020
                BL   delay_custom

                B    game_start

set_hard
                LDR  R0, =mode
                MOV  R1, #1
                STR  R1, [R0]

                BL   lcd_clear
                BL   lcd_line1
                LDR  R0, =str_hard
                BL   lcd_print_string
                MOVW R0, #0x0000
                MOVT R0, #0x0020
                BL   delay_custom

                B    game_start
                LTORG

; game_start - Reset score, init round counter, show score 0
game_start
                LDR  R0, =score
                MOV  R1, #0
                STR  R1, [R0]

                LDR  R0, =rounds_left
                MOV  R1, #GAME_TIME
                STR  R1, [R0]

                BL   lcd_show_scoreboard

; game_loop - Main game loop
game_loop
                LDR  R0, =rounds_left
                LDR  R1, [R0]
                CMP  R1, #0
                BEQ  game_timeout

                SUB  R1, R1, #1
                STR  R1, [R0]

                BL   leds_off

                BL   rand_next
                MOV  R1, #5
                UDIV R2, R0, R1
                MLS  R4, R2, R1, R0

                MOV  R0, R4
                BL   light_led
                MOV  R5, R4

                LDR  R0, =mode
                LDR  R0, [R0]
                CMP  R0, #1
                BNE  wait_button

pick_second
                BL   rand_next
                MOV  R1, #5
                UDIV R2, R0, R1
                MLS  R6, R2, R1, R0
                CMP  R6, R5
                BEQ  pick_second
                MOV  R0, R6
                BL   light_led

; wait_button - Poll buttons during active mole window
wait_button
                LDR  R0, =mode
                LDR  R0, [R0]
                CMP  R0, #1
                BEQ  use_hard_delay

use_easy_delay
                MOVW R7, #0x0000
                MOVT R7, #0x0006
                B    poll_loop

use_hard_delay
                MOVW R7, #0x4
				000
                MOVT R7, #0x0002

poll_loop
                SUBS R7, R7, #1
                BEQ  missed_mole

                BL   read_buttons

                MOV  R1, #1
                LSL  R1, R1, R5
                TST  R0, R1
                BNE  hit_mole

                LDR  R2, =mode
                LDR  R2, [R2]
                CMP  R2, #1
                BNE  poll_loop

                MOV  R1, #1
                LSL  R1, R1, R6
                TST  R0, R1
                BNE  hit_mole

                B    poll_loop

; hit_mole - Correct button pressed in time
hit_mole
                LDR  R0, =score
                LDR  R1, [R0]
                ADD  R1, R1, #1
                STR  R1, [R0]

                BL   lcd_show_scoreboard

                BL   leds_off
                MOV  R0, R5
                BL   light_led
                MOV  R0, #0x20000
                BL   delay_custom
                BL   leds_off
                MOV  R0, #0x20000
                BL   delay_custom
                MOV  R0, R5
                BL   light_led
                MOV  R0, #0x20000
                BL   delay_custom
                BL   leds_off

                LDR  R0, =score
                LDR  R1, [R0]
                CMP  R1, #10
                BEQ  game_win

                B    game_loop

; missed_mole - Time window expired
missed_mole
                MOV  R3, #3
miss_flash_loop
                BL   leds_all_on
                MOV  R0, #0x30000
                BL   delay_custom
                BL   leds_off
                MOV  R0, #0x30000
                BL   delay_custom
                SUBS R3, R3, #1
                BNE  miss_flash_loop

                B    game_loop
                LTORG

; game_timeout - 10 seconds elapsed
game_timeout
                BL   leds_off
                BL   lcd_clear

                BL   lcd_line1
                LDR  R0, =str_timeup1
                BL   lcd_print_string

                BL   lcd_line2
                LDR  R0, =str_score_lbl
                BL   lcd_print_string

                LDR  R0, =score
                LDR  R0, [R0]
                BL   lcd_print_number

                MOVW R0, #0x0000
                MOVT R0, #0x0040
                BL   delay_custom

                B    wait_mode
                LTORG

; game_win - Score reached 10
game_win
                BL   lcd_clear
                BL   lcd_line1
                LDR  R0, =str_win1
                BL   lcd_print_string

                BL   lcd_line2
                LDR  R0, =str_score_lbl
                BL   lcd_print_string
                MOV  R0, #10
                BL   lcd_print_number

                MOV  R3, #5
win_loop
                MOV  R4, #0
win_chase
                MOV  R0, R4
                BL   light_led
                MOV  R0, #0x10000
                BL   delay_custom
                BL   leds_off
                ADD  R4, R4, #1
                CMP  R4, #5
                BNE  win_chase
                SUBS R3, R3, #1
                BNE  win_loop

                MOVW R0, #0x0000
                MOVT R0, #0x0040
                BL   delay_custom

                B    wait_mode
                ENDP
                LTORG

; lcd_show_scoreboard
lcd_show_scoreboard PROC
                PUSH {R0, LR}

                BL   lcd_clear
                BL   lcd_line1
                LDR  R0, =str_score_lbl
                BL   lcd_print_string

                LDR  R0, =score
                LDR  R0, [R0]
                BL   lcd_print_number

                POP  {R0, PC}
                ENDP

; lcd_print_number - print 0-10 as ASCII
lcd_print_number PROC
                PUSH {R0, R1, R2, LR}

                CMP  R0, #10
                BEQ  print_ten

                ADD  R0, R0, #'0'
                BL   lcd_send_data
                B    print_num_done

print_ten
                MOV  R0, #'1'
                BL   lcd_send_data
                MOV  R0, #'0'
                BL   lcd_send_data

print_num_done
                POP  {R0, R1, R2, PC}
                ENDP

; lcd_print_string - null-terminated string in R0
lcd_print_string PROC
                PUSH {R0, R1, LR}
print_str_loop
                LDRB R1, [R0], #1
                CMP  R1, #0
                BEQ  print_str_done
                PUSH {R0}
                MOV  R0, R1
                BL   lcd_send_data
                POP  {R0}
                B    print_str_loop
print_str_done
                POP  {R0, R1, PC}
                ENDP

; lcd_line1 - cursor to row 0 col 0
lcd_line1       PROC
                PUSH {R0, LR}
                MOV  R0, #0x80
                BL   lcd_send_cmd
                POP  {R0, PC}
                ENDP

; lcd_line2 - cursor to row 1 col 0
lcd_line2       PROC
                PUSH {R0, LR}
                MOV  R0, #0xC0
                BL   lcd_send_cmd
                POP  {R0, PC}
                ENDP

; lcd_clear
lcd_clear       PROC
                PUSH {R0, LR}
                MOV  R0, #0x01
                BL   lcd_send_cmd
                MOVW R0, #0x0000
                MOVT R0, #0x0010
                BL   delay_custom
                POP  {R0, PC}
                ENDP

; lcd_init - HD44780 4-bit init sequence
;
; RS is on GPIOB PB5.
; EN and D4-D7 are on GPIOA (PA6-PA10).
lcd_init        PROC
                PUSH {R0, R1, R2, LR}

                ; Clear RS (PB5) low
                LDR  R1, =GPIOB_BASE
                LDR  R0, [R1, #ODR_OFFSET]
                BIC  R0, R0, #LCD_RS_PIN
                STR  R0, [R1, #ODR_OFFSET]

                ; Clear EN and data lines on GPIOA
                LDR  R1, =GPIOA_BASE
                LDR  R0, [R1, #ODR_OFFSET]
                MOVW R2, #(LCD_EN_MASK :OR: LCD_DATA_MASK)
                BIC  R0, R0, R2
                STR  R0, [R1, #ODR_OFFSET]

                ; Power-on delay >40ms (large value safe at 16MHz)
                MOVW R0, #0x0000
                MOVT R0, #0x0060
                BL   delay_custom

                ; --- 3x send nibble 0x03 (function set reset) ---
                MOV  R0, #0x03
                BL   lcd_send_init_nibble
                MOVW R0, #0x0000
                MOVT R0, #0x0010            ; >4.1ms
                BL   delay_custom

                MOV  R0, #0x03
                BL   lcd_send_init_nibble
                MOV  R0, #0x8000            ; >100us
                BL   delay_custom

                MOV  R0, #0x03
                BL   lcd_send_init_nibble
                MOV  R0, #0x8000
                BL   delay_custom

                ; Switch to 4-bit mode
                MOV  R0, #0x02
                BL   lcd_send_init_nibble
                MOV  R0, #0x8000
                BL   delay_custom

                ; Function Set: 4-bit, 2-line, 5x8
                MOV  R0, #0x28
                BL   lcd_send_cmd

                ; Display Off
                MOV  R0, #0x08
                BL   lcd_send_cmd

                ; Clear Display
                MOV  R0, #0x01
                BL   lcd_send_cmd
                MOVW R0, #0x0000
                MOVT R0, #0x0010
                BL   delay_custom

                ; Entry Mode: increment, no shift
                MOV  R0, #0x06
                BL   lcd_send_cmd

                ; Display On, cursor off, blink off
                MOV  R0, #0x0C
                BL   lcd_send_cmd

                POP  {R0, R1, R2, PC}
                ENDP

; lcd_send_init_nibble
; Sends lower nibble of R0 on D4-D7 with RS=0.
; Used ONLY during the 3-step reset in lcd_init.
; R0 bits[3:0] = nibble.
lcd_send_init_nibble PROC
                PUSH {R0, R1, R2, LR}       ; R0 at SP+0

                ; Ensure RS (PB5) is LOW
                LDR  R1, =GPIOB_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                BIC  R2, R2, #LCD_RS_PIN
                STR  R2, [R1, #ODR_OFFSET]

                ; Load GPIOA ODR and clear EN + data lines
                LDR  R1, =GPIOA_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                MOVW R0, #(LCD_EN_MASK :OR: LCD_DATA_MASK)
                BIC  R2, R2, R0

                ; Reload original nibble from stack (R0 is at SP+0)
                LDR  R0, [SP, #0]

                ; Map nibble bits to D4-D7
                TST  R0, #0x01
                ORRNE R2, R2, #LCD_D4
                TST  R0, #0x02
                ORRNE R2, R2, #LCD_D5
                TST  R0, #0x04
                ORRNE R2, R2, #LCD_D6
                TST  R0, #0x08
                ORRNE R2, R2, #LCD_D7

                ; Setup data
                STR  R2, [R1, #ODR_OFFSET]
                NOP
                NOP
                NOP
                NOP

                ; Pulse EN high then low
                ORR  R2, R2, #LCD_EN
                STR  R2, [R1, #ODR_OFFSET]
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                BIC  R2, R2, #LCD_EN
                STR  R2, [R1, #ODR_OFFSET]
                NOP
                NOP
                NOP
                NOP

                POP  {R0, R1, R2, PC}
                ENDP

; lcd_send_cmd - send command byte in R0 (RS=0)
lcd_send_cmd    PROC
                PUSH {R0, LR}
                MOV  R1, #0
                BL   lcd_send_byte_rs
                POP  {R0, PC}
                ENDP

; lcd_send_data - send data byte in R0 (RS=1)
lcd_send_data   PROC
                PUSH {R0, LR}
                MOV  R1, #1
                BL   lcd_send_byte_rs
                POP  {R0, PC}
                ENDP

; lcd_send_byte_rs
;   R0 = byte, R1 = RS flag (0=cmd, 1=data)
; Sends high nibble then low nibble.
lcd_send_byte_rs PROC
                PUSH {R0, R1, R2, R3, R4, LR}

                MOV  R4, R0                 ; save full byte

                ; High nibble
                LSR  R3, R4, #4
                BL   lcd_nibble_out

                ; Low nibble
                AND  R3, R4, #0x0F
                BL   lcd_nibble_out

                ; Post-byte delay
                MOV  R0, #0x8000
                BL   delay_custom

                POP  {R0, R1, R2, R3, R4, PC}
                ENDP

; lcd_nibble_out
;   R3 = nibble (bits 3:0)
;   R1 = RS value (0 or 1)
;
; RS is on GPIOB PB5.
; EN and D4-D7 are on GPIOA.
lcd_nibble_out  PROC
                PUSH {R0, R2, LR}

                ; --- Set RS on GPIOB PB5 ---
                LDR  R0, =GPIOB_BASE
                LDR  R2, [R0, #ODR_OFFSET]
                BIC  R2, R2, #LCD_RS_PIN    ; clear RS first
                CMP  R1, #1
                ORREQ R2, R2, #LCD_RS_PIN   ; set RS if data
                STR  R2, [R0, #ODR_OFFSET]

                ; --- Set data lines on GPIOA, clear EN ---
                LDR  R0, =GPIOA_BASE
                LDR  R2, [R0, #ODR_OFFSET]
                MOVW R0, #(LCD_EN_MASK :OR: LCD_DATA_MASK)
                BIC  R2, R2, R0
                LDR  R0, =GPIOA_BASE        ; reload base

                ; Map nibble to D4-D7
                TST  R3, #0x01
                ORRNE R2, R2, #LCD_D4
                TST  R3, #0x02
                ORRNE R2, R2, #LCD_D5
                TST  R3, #0x04
                ORRNE R2, R2, #LCD_D6
                TST  R3, #0x08
                ORRNE R2, R2, #LCD_D7

                ; Data setup before EN
                STR  R2, [R0, #ODR_OFFSET]
                NOP
                NOP
                NOP
                NOP

                ; Pulse EN high
                ORR  R2, R2, #LCD_EN
                STR  R2, [R0, #ODR_OFFSET]

                ; EN pulse width >= 450ns (10 NOPs safe at 16MHz)
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP

                ; EN low
                BIC  R2, R2, #LCD_EN
                STR  R2, [R0, #ODR_OFFSET]

                ; Hold time after EN falls
                NOP
                NOP
                NOP
                NOP

                POP  {R0, R2, PC}
                ENDP

; light_led - Turn on LED for mole index in R0
;   Mole 0 = PA0,  Mole 1 = PA1,  Mole 2 = PA4
;   Mole 3 = PB0,  Mole 4 = PC1
light_led       PROC
                PUSH {R1, R2, LR}
                CMP  R0, #0
                BEQ  led_pa0
                CMP  R0, #1
                BEQ  led_pa1
                CMP  R0, #2
                BEQ  led_pa4
                CMP  R0, #3
                BEQ  led_pb0
                CMP  R0, #4
                BEQ  led_pc1
                B    light_done

led_pa0
                LDR  R1, =GPIOA_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                ORR  R2, R2, #(1 << 0)
                STR  R2, [R1, #ODR_OFFSET]
                B    light_done
led_pa1
                LDR  R1, =GPIOA_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                ORR  R2, R2, #(1 << 1)
                STR  R2, [R1, #ODR_OFFSET]
                B    light_done
led_pa4
                LDR  R1, =GPIOA_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                ORR  R2, R2, #(1 << 4)
                STR  R2, [R1, #ODR_OFFSET]
                B    light_done
led_pb0
                LDR  R1, =GPIOB_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                ORR  R2, R2, #(1 << 0)
                STR  R2, [R1, #ODR_OFFSET]
                B    light_done
led_pc1
                LDR  R1, =GPIOC_BASE
                LDR  R2, [R1, #ODR_OFFSET]
                ORR  R2, R2, #(1 << 1)
                STR  R2, [R1, #ODR_OFFSET]
light_done
                POP  {R1, R2, PC}
                ENDP

; leds_off - Turn off all 5 game LEDs
; Does NOT touch PB5 (LCD RS) or any LCD lines
leds_off        PROC
                PUSH {R0, R1, R2, LR}

                LDR  R0, =GPIOA_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                MOV  R2, #0x13              ; PA0, PA1, PA4
                BIC  R1, R1, R2
                STR  R1, [R0, #ODR_OFFSET]

                LDR  R0, =GPIOB_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                BIC  R1, R1, #0x01          ; PB0 only - NOT PB5
                STR  R1, [R0, #ODR_OFFSET]

                LDR  R0, =GPIOC_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                BIC  R1, R1, #0x02          ; PC1
                STR  R1, [R0, #ODR_OFFSET]

                POP  {R0, R1, R2, PC}
                ENDP

; leds_all_on - Turn on all 5 game LEDs
; Does NOT touch PB5 (LCD RS) or any LCD lines
leds_all_on     PROC
                PUSH {R0, R1, R2, LR}

                LDR  R0, =GPIOA_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                MOV  R2, #0x13              ; PA0, PA1, PA4
                ORR  R1, R1, R2
                STR  R1, [R0, #ODR_OFFSET]

                LDR  R0, =GPIOB_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                ORR  R1, R1, #0x01          ; PB0 only - NOT PB5
                STR  R1, [R0, #ODR_OFFSET]

                LDR  R0, =GPIOC_BASE
                LDR  R1, [R0, #ODR_OFFSET]
                ORR  R1, R1, #0x02          ; PC1
                STR  R1, [R0, #ODR_OFFSET]

                POP  {R0, R1, R2, PC}
                ENDP

; read_buttons - Returns bitmask in R0:
read_buttons    PROC
                PUSH {R1, R2, LR}
                MOV  R0, #0

                LDR  R1, =GPIOC_BASE
                LDR  R2, [R1, #IDR_OFFSET]
                TST  R2, #(1<<0)
                ORRNE R0, R0, #(1<<0)
                TST  R2, #(1<<2)
                ORRNE R0, R0, #(1<<1)
                TST  R2, #(1<<3)
                ORRNE R0, R0, #(1<<2)

                LDR  R1, =GPIOB_BASE
                LDR  R2, [R1, #IDR_OFFSET]
                TST  R2, #(1<<3)
                ORRNE R0, R0, #(1<<3)
                TST  R2, #(1<<4)
                ORRNE R0, R0, #(1<<4)

                POP  {R1, R2, PC}
                ENDP

; rand_next - 32-bit Galois LFSR
; Returns next value in R0, updates rand_seed
rand_next       PROC
                PUSH {R1, R2, LR}
                LDR  R1, =rand_seed
                LDR  R0, [R1]
                MOV  R2, R0, LSR #1
                TST  R0, #1
                BEQ  rand_no_xor
                MOVW R0, #0xD35C
                MOVT R0, #0xB4BC
                EOR  R2, R2, R0
rand_no_xor
                STR  R2, [R1]
                MOV  R0, R2
                POP  {R1, R2, PC}
                ENDP

; delay_custom - Busy-wait loop; count in R0
delay_custom    PROC
delay_c_loop
                SUBS R0, R0, #1
                BNE  delay_c_loop
                BX   LR
                ENDP

                END

