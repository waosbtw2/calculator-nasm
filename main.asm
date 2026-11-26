;-
default rel
global main

extern XOpenDisplay, XDefaultRootWindow, XCreateSimpleWindow
extern XStoreName, XSelectInput, XMapWindow, XNextEvent, XCloseDisplay
extern XCreateGC, XSetForeground, XFillRectangle, XDrawString, XFreeGC
extern XLookupString, XInternAtom, XSetWMProtocols
extern XLoadQueryFont, XSetFont

KeyPress      equ 2
ButtonPress   equ 4
Expose        equ 12
ClientMessage equ 33
KeyPressMask    equ 1
ButtonPressMask equ 4
ExposureMask    equ 1 << 15

section .data
titulo:   db "Calculadora", 0
fuente:   db "10x20", 0
wmname:   db "WM_DELETE_WINDOW", 0
msg_err:  db "Error"
botones:  db "789/456*123-C0=+"      ;-
cw:       dd 6                       ;-
dy:       dd 5                       ;-

section .bss
display: resq 1
window:  resq 1
gc:      resq 1
wmdel:   resq 1
acc:     resq 1                      ;-
cur:     resq 1                      ;-
op:      resb 1                      ;-
nuevo:   resb 1                      ;-
err:     resb 1                      ;-
chbuf:   resb 1
keybuf:  resb 8
numbuf:  resb 32
event:   resb 192

section .text
main:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 40

    xor  edi, edi
    call XOpenDisplay wrt ..plt
    test rax, rax
    jz   .error
    mov  [display], rax
    mov  rbx, rax                   ;-

    mov  rdi, rbx
    call XDefaultRootWindow wrt ..plt
    mov  rsi, rax                   ;-
    mov  qword [rsp], 0             ;-
    mov  qword [rsp+8], 0           ;-
    mov  qword [rsp+16], 0x202020   ;-
    mov  rdi, rbx
    mov  edx, 100
    mov  ecx, 100
    mov  r8d, 248                   ;-
    mov  r9d, 294                   ;-
    call XCreateSimpleWindow wrt ..plt
    mov  [window], rax
    mov  r12, rax                   ;-

    mov  rdi, rbx
    mov  rsi, r12
    lea  rdx, [titulo]
    call XStoreName wrt ..plt

    mov  rdi, rbx
    mov  rsi, r12
    xor  edx, edx
    xor  ecx, ecx
    call XCreateGC wrt ..plt
    mov  [gc], rax
    mov  r13, rax                   ;-

    ;-
    mov  rdi, rbx
    lea  rsi, [fuente]
    call XLoadQueryFont wrt ..plt
    test rax, rax
    jz   .nofuente
    mov  rdx, [rax+8]               ;-
    mov  rdi, rbx
    mov  rsi, r13
    call XSetFont wrt ..plt
    mov  dword [cw], 10
    mov  dword [dy], 6
.nofuente:

    ;-
    mov  rdi, rbx
    lea  rsi, [wmname]
    xor  edx, edx
    call XInternAtom wrt ..plt
    mov  [wmdel], rax
    mov  rdi, rbx
    mov  rsi, r12
    lea  rdx, [wmdel]
    mov  ecx, 1
    call XSetWMProtocols wrt ..plt

    mov  rdi, rbx
    mov  rsi, r12
    mov  edx, KeyPressMask | ButtonPressMask | ExposureMask
    call XSelectInput wrt ..plt

    mov  rdi, rbx
    mov  rsi, r12
    call XMapWindow wrt ..plt

.loop:
    mov  rdi, rbx
    lea  rsi, [event]
    call XNextEvent wrt ..plt
    mov  eax, [event]
    cmp  eax, Expose
    je   .expose
    cmp  eax, ButtonPress
    je   .click
    cmp  eax, KeyPress
    je   .tecla
    cmp  eax, ClientMessage
    je   .cliente
    jmp  .loop

.expose:
    cmp  dword [event+56], 0        ;-
    jne  .loop
    call dibujar
    jmp  .loop

.cliente:
    mov  rax, [event+56]            ;-
    cmp  rax, [wmdel]
    je   .salir
    jmp  .loop

.click:
    cmp  dword [event+84], 1        ;-
    jne  .loop
    mov  eax, [event+64]            ;-
    sub  eax, 8
    jl   .loop
    xor  edx, edx
    mov  ecx, 60
    div  ecx                        ;-
    cmp  eax, 4
    jge  .loop
    cmp  edx, 52                    ;-
    jge  .loop
    mov  r14d, eax                  ;-
    mov  eax, [event+68]            ;-
    sub  eax, 70
    jl   .loop
    xor  edx, edx
    mov  ecx, 56
    div  ecx
    cmp  eax, 4
    jge  .loop
    cmp  edx, 48
    jge  .loop
    shl  eax, 2
    add  eax, r14d                  ;-
    lea  rcx, [botones]
    movzx edi, byte [rcx+rax]
    call pulsar
    call dibujar
    jmp  .loop

.tecla:
    lea  rdi, [event]
    lea  rsi, [keybuf]
    mov  edx, 8
    xor  ecx, ecx
    xor  r8d, r8d
    call XLookupString wrt ..plt
    test eax, eax
    jz   .loop                      ;-
    movzx edi, byte [keybuf]
    cmp  edi, 13                    ;-
    je   .enter
    cmp  edi, 'c'
    je   .minc
    cmp  edi, 'x'                   ;-
    je   .porx
    cmp  edi, 'q'
    je   .salir
    cmp  edi, 27                    ;-
    je   .salir
    jmp  .enviar
.enter:
    mov  edi, '='
    jmp  .enviar
.minc:
    mov  edi, 'C'
    jmp  .enviar
.porx:
    mov  edi, '*'
.enviar:
    call pulsar
    call dibujar
    jmp  .loop

.salir:
    mov  rdi, rbx
    mov  rsi, r13
    call XFreeGC wrt ..plt
    mov  rdi, rbx
    call XCloseDisplay wrt ..plt
    xor  eax, eax
    jmp  .fin
.error:
    mov  eax, 1
.fin:
    add  rsp, 40
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

;-
pulsar:
    movzx eax, dil
    cmp  al, 'C'
    jne  .noC
    mov  qword [acc], 0
    mov  qword [cur], 0
    mov  byte [op], 0
    mov  byte [nuevo], 0
    mov  byte [err], 0
    ret
.noC:
    cmp  byte [err], 0
    jne  .ret                       ;-
    cmp  al, 8                      ;-
    jne  .nobs
    cmp  byte [nuevo], 0
    jne  .ret
    mov  rax, [cur]
    cqo
    mov  rcx, 10
    idiv rcx
    mov  [cur], rax
    ret
.nobs:
    cmp  al, '0'
    jb   .oper
    cmp  al, '9'
    ja   .oper

    ;-
    cmp  byte [nuevo], 0
    je   .acum
    mov  qword [cur], 0
    mov  byte [nuevo], 0
.acum:
    mov  rcx, [cur]
    mov  rdx, 100000000000000       ;-
    cmp  rcx, rdx
    jge  .ret
    sub  eax, '0'
    imul rcx, rcx, 10
    add  rcx, rax
    mov  [cur], rcx
    ret

    ;-
.oper:
    cmp  al, '+'
    je   .ok
    cmp  al, '-'
    je   .ok
    cmp  al, '*'
    je   .ok
    cmp  al, '/'
    je   .ok
    cmp  al, '='
    jne  .ret
.ok:
    mov  r8d, eax                   ;-
    cmp  byte [op], 0
    je   .sinop
    cmp  byte [nuevo], 0
    jne  .sinop                     ;-
    mov  rax, [acc]
    mov  rcx, [cur]
    movzx edx, byte [op]
    cmp  dl, '+'
    jne  .n1
    add  rax, rcx
    jmp  .res
.n1:
    cmp  dl, '-'
    jne  .n2
    sub  rax, rcx
    jmp  .res
.n2:
    cmp  dl, '*'
    jne  .n3
    imul rax, rcx
    jmp  .res
.n3:                                ;-
    test rcx, rcx
    jz   .diverr
    cqo
    idiv rcx
.res:
    mov  [cur], rax
.sinop:
    mov  rax, [cur]
    mov  [acc], rax
    mov  byte [nuevo], 1
    cmp  r8b, '='
    jne  .setop
    mov  byte [op], 0
    ret
.setop:
    mov  [op], r8b
    ret
.diverr:
    mov  byte [err], 1
.ret:
    ret

;-
num2str:
    lea  rsi, [numbuf+30]
    xor  r8d, r8d
    test rax, rax
    jns  .pos
    neg  rax
    mov  r8d, 1
.pos:
    mov  r9d, 10
.dig:
    xor  edx, edx
    div  r9
    add  dl, '0'
    mov  [rsi], dl
    dec  rsi
    test rax, rax
    jnz  .dig
    test r8d, r8d
    jz   .fin
    mov  byte [rsi], '-'
    dec  rsi
.fin:
    inc  rsi
    lea  rdx, [numbuf+31]
    sub  rdx, rsi
    ret

;-
setfg:
    push rbp
    mov  rbp, rsp
    mov  rdx, rdi
    mov  rdi, [display]
    mov  rsi, [gc]
    call XSetForeground wrt ..plt
    pop  rbp
    ret

;-
frect:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub  rsp, 16
    mov  ebx, edi
    mov  r12d, esi
    mov  r13d, edx
    mov  r14d, ecx
    mov  rdi, [display]
    mov  rsi, [gc]
    mov  rdx, r8
    call XSetForeground wrt ..plt
    mov  rdi, [display]
    mov  rsi, [window]
    mov  rdx, [gc]
    mov  ecx, ebx
    mov  r8d, r12d
    mov  r9d, r13d
    mov  [rsp], r14
    call XFillRectangle wrt ..plt
    add  rsp, 16
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

;-
texto:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16
    mov  [rsp], rcx
    mov  r9, rdx
    mov  ecx, edi
    mov  r8d, esi
    mov  rdi, [display]
    mov  rsi, [window]
    mov  rdx, [gc]
    call XDrawString wrt ..plt
    leave
    ret

;-
dibujar:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    ;-
    mov  edi, 8
    mov  esi, 8
    mov  edx, 232
    mov  ecx, 50
    mov  r8d, 0x101010
    call frect
    mov  edi, 0xffffff
    call setfg
    cmp  byte [err], 0
    je   .num
    lea  rsi, [msg_err]
    mov  edx, 5
    jmp  .pintar
.num:
    mov  rax, [cur]
    call num2str
.pintar:                            ;-
    mov  ecx, edx
    mov  r12, rsi
    mov  r13, rdx
    imul ecx, dword [cw]
    mov  edi, 222                   ;-
    sub  edi, ecx
    cmp  edi, 12
    jge  .xok
    mov  edi, 12
.xok:
    mov  esi, 33
    add  esi, dword [dy]
    mov  rdx, r12
    mov  rcx, r13
    call texto

    ;-
    xor  r14d, r14d
.btn:
    cmp  r14d, 16
    jge  .fin
    mov  eax, r14d
    shr  eax, 2                     ;-
    imul eax, 56
    add  eax, 70
    mov  r12d, eax                  ;-
    mov  eax, r14d
    and  eax, 3                     ;-
    imul eax, 60
    add  eax, 8
    mov  ebx, eax                   ;-
    lea  rax, [botones]
    movzx r13d, byte [rax+r14]      ;-

    mov  r8d, 0x3c3c3c              ;-
    cmp  r13b, 'C'
    jne  .c1
    mov  r8d, 0xb03030              ;-
    jmp  .cdone
.c1:
    cmp  r13b, '0'
    jb   .oper
    cmp  r13b, '9'
    jbe  .cdone
.oper:
    mov  r8d, 0xd9822b              ;-
.cdone:
    mov  edi, ebx
    mov  esi, r12d
    mov  edx, 52
    mov  ecx, 48
    call frect

    mov  edi, 0xffffff
    call setfg
    mov  eax, 52
    sub  eax, dword [cw]
    shr  eax, 1
    add  eax, ebx
    mov  edi, eax                   ;-
    mov  esi, r12d
    add  esi, 24
    add  esi, dword [dy]            ;-
    mov  [chbuf], r13b
    lea  rdx, [chbuf]
    mov  ecx, 1
    call texto
    inc  r14d
    jmp  .btn
.fin:
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
