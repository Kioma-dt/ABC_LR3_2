cpu 386
bits 16
org 0x100

SEL_CODE equ 0x08
SEL_DATA equ 0x10
SEL_TSS1 equ 0x18
SEL_TSS2 equ 0x20
SEL_TSS3 equ 0x28
SEL_FLAT equ 0x30
VIDEO    equ 0xB8000
DELAY    equ 3000000            

start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    smsw ax
    test ax, 1
    jnz dos_error
    mov ax, 0x0003
    int 0x10
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax

    movzx ebx, ax
    shl ebx, 4
    mov eax, ebx
    mov di, gdt+8
    call set_base
    mov eax, ebx
    mov di, gdt+16
    call set_base

    mov eax, gdt
    add eax, ebx
    mov [gdtr+2], eax

    mov eax, tss1
    add eax, ebx
    mov di, gdt_tss1
    call set_base
    mov eax, tss2
    add eax, ebx
    mov di, gdt_tss2
    call set_base
    mov eax, tss3
    add eax, ebx
    mov di, gdt_tss3
    call set_base

    mov al, 0x80
    out 0x70, al
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1                  
    mov cr0, eax
    jmp dword SEL_CODE:pm_entry

dos_error:
    sti
    mov dx, dos_error_msg
    mov ah, 9
    int 0x21
    mov ax, 0x4C01
    int 0x21
dos_error_msg db "Run in real-mode DOS without EMM386.",13,10,"$"

set_base:
    mov [di+2], ax
    shr eax, 16
    mov [di+4], al
    mov [di+7], ah
    ret

bits 32
pm_entry:
    mov ax, SEL_DATA
    mov ds, ax
    mov fs, ax
    mov ss, ax
    mov ax, SEL_FLAT
    mov es, ax
    mov gs, ax
    mov esp, stack1_top
    cld

    mov esi, title_msg
    mov edi, VIDEO
    call print_string
    mov esi, task1_msg
    mov edi, VIDEO+160*3
    call print_string
    mov esi, task2_msg
    mov edi, VIDEO+160*5
    call print_string
    mov esi, task3_msg
    mov edi, VIDEO+160*7
    call print_string

    mov ax, SEL_TSS1
    ltr ax  
    jmp task1

task1:
    xor ebx, ebx              
    mov esi, 1                 
    mov edx, VIDEO+160*3+2*25   
    mov ebp, next2
    jmp task_loop
task2:
    xor ebx, ebx
    mov esi, 2
    mov edx, VIDEO+160*5+2*25
    mov ebp, next3
    jmp task_loop
task3:
    xor ebx, ebx
    mov esi, 3
    mov edx, VIDEO+160*7+2*25
    mov ebp, next1

task_loop:
    add ebx, esi
    call print_hex32
    mov ecx, DELAY
.delay:
    loop .delay
    jmp far [ebp]              
    jmp task_loop


print_hex32:
    pushad
    mov eax, ebx
    mov edi, edx
    mov ecx, 8
.digit:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0F
    mov dl, [hex_digits+ebx]
    mov dh, 0x0A
    mov [gs:edi], dx
    add edi, 2
    loop .digit
    popad
    ret

print_string:
    mov ah, 0x0F
.char:
    lodsb
    test al, al
    jz .done
    stosw
    jmp .char
.done:
    ret

hex_digits db '0123456789ABCDEF'
title_msg db 'PROTECTED MODE: 3 TSS tasks',0
task1_msg db 'Task 1  step +1   count: 00000000',0
task2_msg db 'Task 2  step +2   count: 00000000',0
task3_msg db 'Task 3  step +3   count: 00000000',0
error_msg db 'CPU EXCEPTION: execution stopped',0

next1 dd 0
    dw SEL_TSS1
next2 dd 0
    dw SEL_TSS2
next3 dd 0
    dw SEL_TSS3

align 8, db 0
gdt:
    dq 0
    dq 0x00CF9A000000FFFF 
    dq 0x00CF92000000FFFF     
gdt_tss1:
    dw 103, 0
    db 0, 0x89, 0, 0          
gdt_tss2:
    dw 103, 0
    db 0, 0x89, 0, 0
gdt_tss3:
    dw 103, 0
    db 0, 0x89, 0, 0
    dq 0x00CF92000000FFFF     
gdt_end:
gdtr:
    dw gdt_end-gdt-1
    dd gdt

%macro TASK_TSS 2              
    dd 0                      
    dd %2, SEL_DATA            
    dd 0, 0, 0, 0            
    dd 0                     
    dd %1, 2                 
    dd 0, 0, 0, 0             
    dd %2, 0, 0, 0            
    dd SEL_FLAT, SEL_CODE     
    dd SEL_DATA, SEL_DATA      
    dd SEL_DATA, SEL_FLAT     
    dd 0                     
    dw 0, 104               
%endmacro

align 4, db 0
tss1: TASK_TSS task1, stack1_top
tss2: TASK_TSS task2, stack2_top
tss3: TASK_TSS task3, stack3_top

align 16, db 0
stack1: times 512 db 0
stack1_top:
stack2: times 512 db 0
stack2_top:
stack3: times 512 db 0
stack3_top:

