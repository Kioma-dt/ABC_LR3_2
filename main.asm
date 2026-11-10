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
    mov ax, 0x0003              ; Текстовый режим 80 x 25.
    int 0x10
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; Линейная база программы определяется DOS при загрузке COM.
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

    ; У дескриптора база разнесена по трём полям.
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

    mov al, 0x80               ; Отключить NMI на время демонстрации.
    out 0x70, al
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1                  ; CR0.PE = 1.
    mov cr0, eax
    jmp dword SEL_CODE:pm_entry ; Загрузить CS, начать 32-разрядный код.

dos_error:
    sti
    mov dx, dos_error_msg
    mov ah, 9
    int 0x21
    mov ax, 0x4C01
    int 0x21
dos_error_msg db "Run in real-mode DOS without EMM386.",13,10,"$"

set_base:                  ; EAX = адрес TSS, DI = дескриптор.
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
    ltr ax                     ; Назначить TSS текущему контексту.
    ; LTR не загружает регистры из TSS и не выполняет переключение.
    jmp task1

; При первом запуске задачи задают свои регистры.
; При следующих переключениях CPU продолжает после JMP FAR в task_loop.
task1:
    xor ebx, ebx               ; Счётчик хранится в регистре каждой задачи.
    mov esi, 1                 ; Шаг первой задачи.
    mov edx, VIDEO+160*3+2*25   ; Адрес восьми цифр на экране.
    mov ebp, next2             ; Указатель на TSS следующей задачи.
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
    jmp far [ebp]              ; CPU сохраняет текущий TSS и загружает новый.
    jmp task_loop              ; Сюда вернёмся, когда снова выберут эту задачу.

; EBX = значение, EDX = экранный адрес. Сохраняет все общие регистры.
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

; ESI = строка с нулём, EDI = адрес в видеопамяти.
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

.halt:
    hlt
    jmp .halt                  ; Не возвращаемся; код ошибки удалять не нужно.

hex_digits db '0123456789ABCDEF'
title_msg db 'PROTECTED MODE: 3 TSS tasks',0
task1_msg db 'Task 1  step +1   count: 00000000',0
task2_msg db 'Task 2  step +2   count: 00000000',0
task3_msg db 'Task 3  step +3   count: 00000000',0
error_msg db 'CPU EXCEPTION: execution stopped',0

; У JMP FAR на TSS смещение игнорируется, важен селектор дескриптора.
next1 dd 0
    dw SEL_TSS1
next2 dd 0
    dw SEL_TSS2
next3 dd 0
    dw SEL_TSS3

align 8, db 0
gdt:
    dq 0
    dq 0x00CF9A000000FFFF      ; Код: база программы, предел 4 ГБ, D=1.
    dq 0x00CF92000000FFFF      ; Данные: база программы, предел 4 ГБ.
gdt_tss1:
    dw 103, 0
    db 0, 0x89, 0, 0           ; Present, доступный 32-битный TSS.
gdt_tss2:
    dw 103, 0
    db 0, 0x89, 0, 0
gdt_tss3:
    dw 103, 0
    db 0, 0x89, 0, 0
    dq 0x00CF92000000FFFF      ; Плоский сегмент для видеопамяти.
gdt_end:
gdtr:
    dw gdt_end-gdt-1
    dd gdt

; Формат 32-битного TSS: 104 байта. Макрос только убирает повторение полей.
; В слотах сегментных регистров старшие 16 бит зарезервированы (= 0).
%macro TASK_TSS 2              ; Начальный EIP и вершина собственного стека.
    dd 0                      ; 00h: backlink и резерв.
    dd %2, SEL_DATA            ; 04h: ESP0, SS0 и резерв.
    dd 0, 0, 0, 0             ; 0Ch: ESP1, SS1, ESP2, SS2.
    dd 0                      ; 1Ch: CR3, страничная адресация выключена.
    dd %1, 2                  ; 20h: EIP, EFLAGS (IF=0, NT=0).
    dd 0, 0, 0, 0             ; 28h: EAX, ECX, EDX, EBX.
    dd %2, 0, 0, 0            ; 38h: ESP, EBP, ESI, EDI.
    dd SEL_FLAT, SEL_CODE      ; 48h: ES, CS.
    dd SEL_DATA, SEL_DATA      ; 50h: SS, DS.
    dd SEL_DATA, SEL_FLAT      ; 58h: FS, GS.
    dd 0                      ; 60h: LDT и резерв; LDT не используется.
    dw 0, 104                 ; 64h: T=0, карта I/O за пределом TSS.
%endmacro

align 4, db 0
tss1: TASK_TSS task1, stack1_top
tss2: TASK_TSS task2, stack2_top
tss3: TASK_TSS task3, stack3_top

; Три отдельных стека по 512 байт, растут к меньшим адресам.
align 16, db 0
stack1: times 512 db 0
stack1_top:
stack2: times 512 db 0
stack2_top:
stack3: times 512 db 0
stack3_top:

