; register data:
; r8: terminal size (rows)
; r9: columns modulo -> backMargin
; r10: terminal size (in border)
; r15: upperMargin
; rbp: row remainder -> downerMargin
; rbx: formula for pattern
;
; reg| purpose                              | location
; r12: counter for rows in border           ; drawLoop1
; r12: counter for columns (safe with pop)  ; drawLine2 / drawLine3 / drawBorderLine
; r13: parity and cache (safe with pop)     ; calculateColumns / calculateRows / drawLoop1
; r13: counter for pattern loop             ; drawLine3
; r14: counter for loops in margins         ; drawUpperMargin / drawDownerMargin / drawFrontMargin / drawBackMargin
; rbx: division                             ; getTerminalSize / calculateColumns / calculateRows
;
; r11, rsi and rdx are free - use only out of syscalls

section .data
    proc_name db "snake", 0

    enter_alt       db 0x1b, '[?1049h'
    enter_alt_len   equ $ - enter_alt
    clear_scr       db 0x1b, '[2J'
    clear_scr_len   equ $ - clear_scr
    exit_alt        db 0x1b, '[?1049l'
    exit_alt_len    equ $ - exit_alt
    hide_cur        db 0x1b, '[?25l'
    hide_cur_len    equ $ - hide_cur
    show_cur        db 0x1b, '[?25h'
    show_cur_len    equ $ - show_cur
    home            db 0x1b, '[H'
    home_len        equ $ - home

    grid db 0xe2, 0x95, 0x94,       ; Index 0: ╔
         db 0xe2, 0x95, 0x97,       ; Index 3: ╗
         db 0xe2, 0x95, 0x9a,       ; Index 6: ╚
         db 0xe2, 0x95, 0x9d,       ; Index 9: ╝
         db 0xe2, 0x95, 0x90,       ; Index 12: ═
         db 0xe2, 0x95, 0x91,       ; Index 15: ║
         db 0xc2, 0xb7,             ; Index 18: ·
         db 0x20,                   ; Index 20: <space>
         db 0x0a                    ; Index 21: \n (= new line)

section .bss
    winsize_buf resb 8
    sa_new      resb 32
    sa_old_int  resb 32
    sa_old_term resb 32
    termios_old resb 60
    termios_new resb 60

section .text
    global _start

_start:
    mov rax, 157
    mov rdi, 15
    lea rsi, [proc_name]
    xor rdx, rdx
    xor r10, r10
    xor r8, r8
    syscall

    call enter_tui
    call raw_mode
    call install_handlers


    call getTerminalSize

    call calculateRows
    mov r14, 0
    call drawUpperMargin

    push r15

    call calculateColumns
    call drawFrontMargin
    call drawEdge1
    call drawBorderLine
    call drawEdge2
    call drawBackMargin
    mov r12, 0

    call drawLoop1

    call drawFrontMargin
    call drawEdge3
    mov r12, 0
    call drawBorderLine
    call drawEdge4
    call drawBackMargin

    pop r15

    mov r14, 0
    call drawDownerMargin

    call wait_forever

enter_tui:
    mov rax, 1
    mov rdi, 1
    lea rsi, [enter_alt]
    mov rdx, enter_alt_len
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [clear_scr]
    mov rdx, clear_scr_len
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [hide_cur]
    mov rdx, hide_cur_len
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [home]
    mov rdx, home_len
    syscall
    ret

raw_mode:
    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5401
    lea rdx, [termios_old]
    syscall

    lea rsi, [termios_old]
    lea rdi, [termios_new]
    mov rcx, 60
    rep movsb

    and dword [termios_new + 12], ~(0x8 | 0x2)
    or dword [termios_new + 12], 0x1

    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5402
    lea rdx, [termios_new]
    syscall
    ret

restore_termios:
    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5402
    lea rdx, [termios_old]
    syscall
    ret

install_handlers:
    lea rax, [cleanup]
    mov [sa_new], rax

    mov qword [sa_new + 8], 0x04000000
    lea rax, [restorer]
    mov [sa_new + 16], rax
    mov qword [sa_new + 24], 0

    mov rax, 13
    mov rdi, 2
    lea rsi, [sa_new]
    lea rdx, [sa_old_int]
    mov r10, 8
    syscall

    mov rax, 13
    mov rdi, 15
    lea rsi, [sa_new]
    lea rdx, [sa_old_term]
    mov r10, 8
    syscall
    ret

restorer:
    mov rax, 15
    syscall

cleanup:
    call restore_termios
    
    mov rax, 1
    mov rdi, 1
    lea rsi, [show_cur]
    mov rdx, show_cur_len
    syscall
    
    mov rax, 1
    mov rdi, 1
    lea rsi, [exit_alt]
    mov rdx, exit_alt_len
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall

getTerminalSize:
    mov rax, 16
    mov rdi, 1
    mov rsi, 0x5413
    mov rdx, winsize_buf
    syscall

    ; -- columns --
    ; rbx: 1 (dot) + 3 (spaces) = 4 -> the first/last dot is subtracted in rax
    movzx ax, word [winsize_buf + 2]
    sub rax, 5
    mov rbx, 4
    mov rdx, 0
    div rbx
    mov r8, rax
    mov r9, rdx

    ; -- rows
    movzx ax, word [winsize_buf + 0]
    sub rax, 3
    mov rbx, 2
    mov rdx, 0
    div rbx
    mov r10, rax
    mov rbp, rdx

    ret

; --- horizontal: cells per row, left/right margin, pattern width ---
calculateColumns:
    mov r13, r9
    and r13, 1

    mov rax, r9
    mov rbx, 2
    xor rdx, rdx
    div rbx
    mov r15, rax 
    mov r9, rax

    mov rax, r8
    imul rax, rax, 4
    add rax, 3
    mov rbx, rax

    cmp r13, 1
    je appendMargin
    ret

; --- vertical: inner rows, upper/downer margin ---
calculateRows:  
    movzx rax, word [winsize_buf]
    sub rax, 2
    test rax, 1
    jnz .haveR10
    dec rax

.haveR10:
    cmp rax, 1
    jge .r10ok
    mov rax, 1

.r10ok:
    mov r10, rax        

    movzx rbx, word [winsize_buf]
    sub rbx, rax
    sub rbx, 2          

    mov rax, rbx
    shr rax, 1
    mov r15, rax  
    mov rbp, rbx
    sub rbp, rax 
    ret

appendMargin:
    inc r9
    ret

drawUpperMargin:
    cmp r14, r15
    je goBack

    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 20
    mov rdx, 2
    syscall

    inc r14
    jmp drawUpperMargin

drawDownerMargin:
    cmp r14, rbp
    je goBack

    mov rax, 1
    mov rdi, 1
    lea rsi, [grid + 21]
    mov rdx, 1
    syscall

    inc r14
    jmp drawDownerMargin

drawLoop1:
    cmp r12, r10
    je goBack

    mov r14, 0

    call drawFrontMargin
    call drawLineBorder

    mov r13, r12
    and r13, 1

    cmp r13, 0
    je gotoLine2
    jmp gotoLine3

drawLoop2:
    mov r14, 0

    call drawLineBorder
    call drawBackMargin

    inc r12
    jmp drawLoop1

gotoLine2:
    push r12
    mov r12, 0
    call drawLine2
    pop r12
    jmp drawLoop2

gotoLine3:
    push r12
    mov r12, 0
    call drawLine3
    pop r12
    jmp drawLoop2

drawFrontMargin:
    cmp r14, r15
    je goBack

    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 20
    mov rdx, 1
    syscall

    inc r14
    jmp drawFrontMargin

drawBackMargin:
    cmp r14, r9
    je goBack

    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 20
    mov rdx, 1
    syscall

    inc r14
    jmp drawBackMargin

goBack:
    mov r14, 0
    ret

drawEdge1:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid
    mov rdx, 3
    syscall

    mov r14, 0
    jmp goBack

drawEdge2:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 3
    mov rdx, 3
    syscall

    mov r14, 0
    jmp goBack

drawEdge3:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 6
    mov rdx, 3
    syscall

    mov r14, 0
    jmp goBack

drawEdge4:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 9
    mov rdx, 3
    syscall

    mov r14, 0
    jmp goBack

drawBorderLine:                  ; border line
    cmp r12, rbx
    je goBack

    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 12
    mov rdx, 3
    syscall

    inc r12
    jmp drawBorderLine

drawLine2:                      ; space line
    cmp r12, rbx
    je goBack

    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 20
    mov rdx, 1
    syscall

    inc r12
    jmp drawLine2

drawLine3:
    cmp r12, rbx
    je goBack

    test r12, 1
    jnz .drawDot

    mov r13, 3

.drawSpace:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 20
    mov rdx, 1
    syscall

    inc r12
    dec r13
    jnz .drawSpace
    jmp drawLine3

.drawDot:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 18
    mov rdx, 2
    syscall

    inc r12
    jmp drawLine3

drawLineBorder:
    mov rax, 1
    mov rdi, 1
    mov rsi, grid + 15
    mov rdx, 3
    syscall

    ret

wait_forever:
    mov rax, 34
    syscall
    jmp wait_forever
