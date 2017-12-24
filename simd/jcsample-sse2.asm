;
; jcsample.asm - downsampling (SSE2)
;
; Copyright 2009 Pierre Ossman <ossman@cendio.se> for Cendio AB
;
; Based on
; x86 SIMD extension for IJG JPEG library
; Copyright (C) 1999-2006, MIYASAKA Masaru.
; For conditions of distribution and use, see copyright notice in jsimdext.inc
;
; This file should be assembled with NASM (Netwide Assembler),
; can *not* be assembled with Microsoft's MASM or any compatible
; assembler (including Borland's Turbo Assembler).
; NASM is available from http://nasm.sourceforge.net/ or
; http://sourceforge.net/project/showfiles.php?group_id=6208
;
; [TAB8]

%include "jsimdext.inc"

; --------------------------------------------------------------------------
        SECTION SEG_TEXT
        BITS    32
;
; Downsample pixel values of a single component.
; This version handles the common case of 2:1 horizontal and 1:1 vertical,
; without smoothing.
;
; GLOBAL(void)
; jsimd_h2v1_downsample_sse2 (JDIMENSION image_width, int max_v_samp_factor,
;                             JDIMENSION v_samp_factor, JDIMENSION width_blocks,
;                             JSAMPARRAY input_data, JSAMPARRAY output_data);
;

%define img_width(b)    (b)+8           ; JDIMENSION image_width
%define max_v_samp(b)   (b)+12          ; int max_v_samp_factor
%define v_samp(b)       (b)+16          ; JDIMENSION v_samp_factor
%define width_blks(b)   (b)+20          ; JDIMENSION width_blocks
%define input_data(b)   (b)+24          ; JSAMPARRAY input_data
%define output_data(b)  (b)+28          ; JSAMPARRAY output_data

        align   16
        global  EXTN(jsimd_h2v1_downsample_sse2)

EXTN(jsimd_h2v1_downsample_sse2):
        push    ebp
        mov     ebp,esp
;       push    ebx             ; unused
;       push    ecx             ; need not be preserved
;       push    edx             ; need not be preserved
        push    esi
        push    edi

        mov     ecx, JDIMENSION [width_blks(ebp)]
        shl     ecx,3                   ; imul ecx,DCTSIZE (ecx = output_cols)
        jz      near .return

        mov     edx, JDIMENSION [img_width(ebp)]

        ; -- expand_right_edge

        push    ecx
        shl     ecx,1                           ; output_cols * 2
        sub     ecx,edx
        jle     short .expand_end

        mov     eax, INT [max_v_samp(ebp)]
        test    eax,eax
        jle     short .expand_end

        cld
        mov     esi, JSAMPARRAY [input_data(ebp)]       ; input_data
        alignx  16,7
.expandloop:
        push    eax
        push    ecx

        mov     edi, JSAMPROW [esi]
        add     edi,edx
        mov     al, JSAMPLE [edi-1]

%ifdef COMPILING_FOR_NACL
.rep_replace:
        mov     byte [edi],al       ; Write the value in AL to memory
        inc     edi                 ; Bump EDI to next byte in the buffer
        dec     ecx                 ; Decrement ECX by one position
        jnz     .rep_replace        ; And loop again until ECX is 0
%else
        rep stosb
%endif

        pop     ecx
        pop     eax

        add     esi, byte SIZEOF_JSAMPROW
        dec     eax
        jg      short .expandloop

.expand_end:
        pop     ecx                             ; output_cols

        ; -- h2v1_downsample

        mov     eax, JDIMENSION [v_samp(ebp)]   ; rowctr
        test    eax,eax
        jle     near .return

        mov     edx, 0x00010000         ; bias pattern
        movd    xmm7,edx
        pcmpeqw xmm6,xmm6
        pshufd  xmm7,xmm7,0x00          ; xmm7={0, 1, 0, 1, 0, 1, 0, 1}
        psrlw   xmm6,BYTE_BIT           ; xmm6={0xFF 0x00 0xFF 0x00 ..}

        mov     esi, JSAMPARRAY [input_data(ebp)]       ; input_data
        mov     edi, JSAMPARRAY [output_data(ebp)]      ; output_data
        alignx  16,7
.rowloop:
        push    ecx
        push    edi
        push    esi

        mov     esi, JSAMPROW [esi]             ; inptr
        mov     edi, JSAMPROW [edi]             ; outptr

        cmp     ecx, byte SIZEOF_XMMWORD
        jae     short .columnloop
        alignx  16,7

.columnloop_r8:
        movdqa  xmm0, XMMWORD [esi+0*SIZEOF_XMMWORD]
        pxor    xmm1,xmm1
        mov     ecx, SIZEOF_XMMWORD
        jmp     short .downsample
        alignx  16,7

.columnloop:
        movdqa  xmm0, XMMWORD [esi+0*SIZEOF_XMMWORD]
        movdqa  xmm1, XMMWORD [esi+1*SIZEOF_XMMWORD]

.downsample:
        movdqa  xmm2,xmm0
        movdqa  xmm3,xmm1

        pand    xmm0,xmm6
        psrlw   xmm2,BYTE_BIT
        pand    xmm1,xmm6
        psrlw   xmm3,BYTE_BIT

        paddw   xmm0,xmm2
        paddw   xmm1,xmm3
        paddw   xmm0,xmm7
        paddw   xmm1,xmm7
        psrlw   xmm0,1
        psrlw   xmm1,1

        packuswb xmm0,xmm1

        movdqa  XMMWORD [edi+0*SIZEOF_XMMWORD], xmm0

        sub     ecx, byte SIZEOF_XMMWORD        ; outcol
        add     esi, byte 2*SIZEOF_XMMWORD      ; inptr
        add     edi, byte 1*SIZEOF_XMMWORD      ; outptr
        cmp     ecx, byte SIZEOF_XMMWORD
        jae     short .columnloop
        test    ecx,ecx
%ifdef COMPILING_FOR_NACL
        jnz     near .columnloop_r8
%else
        jnz     short .columnloop_r8
%endif

        pop     esi
        pop     edi
        pop     ecx

        add     esi, byte SIZEOF_JSAMPROW       ; input_data
        add     edi, byte SIZEOF_JSAMPROW       ; output_data
        dec     eax                             ; rowctr
        jg      near .rowloop

.return:
        pop     edi
        pop     esi
;       pop     edx             ; need not be preserved
;       pop     ecx             ; need not be preserved
;       pop     ebx             ; unused
        pop     ebp
        ret

; --------------------------------------------------------------------------
;
; Downsample pixel values of a single component.
; This version handles the standard case of 2:1 horizontal and 2:1 vertical,
; without smoothing.
;
; GLOBAL(void)
; jsimd_h2v2_downsample_sse2 (JDIMENSION image_width, int max_v_samp_factor,
;                             JDIMENSION v_samp_factor, JDIMENSION width_blocks,
;                             JSAMPARRAY input_data, JSAMPARRAY output_data);
;

%define img_width(b)    (b)+8           ; JDIMENSION image_width
%define max_v_samp(b)   (b)+12          ; int max_v_samp_factor
%define v_samp(b)       (b)+16          ; JDIMENSION v_samp_factor
%define width_blks(b)   (b)+20          ; JDIMENSION width_blocks
%define input_data(b)   (b)+24          ; JSAMPARRAY input_data
%define output_data(b)  (b)+28          ; JSAMPARRAY output_data

        align   16
        global  EXTN(jsimd_h2v2_downsample_sse2)

EXTN(jsimd_h2v2_downsample_sse2):
        push    ebp
        mov     ebp,esp
;       push    ebx             ; unused
;       push    ecx             ; need not be preserved
;       push    edx             ; need not be preserved
        push    esi
        push    edi

        mov     ecx, JDIMENSION [width_blks(ebp)]
        shl     ecx,3                   ; imul ecx,DCTSIZE (ecx = output_cols)
        jz      near .return

        mov     edx, JDIMENSION [img_width(ebp)]

        ; -- expand_right_edge

        push    ecx
        shl     ecx,1                           ; output_cols * 2
        sub     ecx,edx
        jle     short .expand_end

        mov     eax, INT [max_v_samp(ebp)]
        test    eax,eax
        jle     short .expand_end

        cld
        mov     esi, JSAMPARRAY [input_data(ebp)]       ; input_data
        alignx  16,7
.expandloop:
        push    eax
        push    ecx

        mov     edi, JSAMPROW [esi]
        add     edi,edx
        mov     al, JSAMPLE [edi-1]

%ifdef COMPILING_FOR_NACL
.rep_replace:
        mov     byte [edi],al       ; Write the value in AL to memory
        inc     edi                 ; Bump EDI to next byte in the buffer
        dec     ecx                 ; Decrement ECX by one position
        jnz     .rep_replace        ; And loop again until ECX is 0
%else
        rep stosb
%endif

        pop     ecx
        pop     eax

        add     esi, byte SIZEOF_JSAMPROW
        dec     eax
        jg      short .expandloop

.expand_end:
        pop     ecx                             ; output_cols

        ; -- h2v2_downsample

        mov     eax, JDIMENSION [v_samp(ebp)]   ; rowctr
        test    eax,eax
        jle     near .return

        mov     edx, 0x00020001         ; bias pattern
        movd    xmm7,edx
        pcmpeqw xmm6,xmm6
        pshufd  xmm7,xmm7,0x00          ; xmm7={1, 2, 1, 2, 1, 2, 1, 2}
        psrlw   xmm6,BYTE_BIT           ; xmm6={0xFF 0x00 0xFF 0x00 ..}

        mov     esi, JSAMPARRAY [input_data(ebp)]       ; input_data
        mov     edi, JSAMPARRAY [output_data(ebp)]      ; output_data
        alignx  16,7
.rowloop:
        push    ecx
        push    edi
        push    esi

        mov     edx, JSAMPROW [esi+0*SIZEOF_JSAMPROW]   ; inptr0
        mov     esi, JSAMPROW [esi+1*SIZEOF_JSAMPROW]   ; inptr1
        mov     edi, JSAMPROW [edi]                     ; outptr

        cmp     ecx, byte SIZEOF_XMMWORD
        jae     short .columnloop
        alignx  16,7

.columnloop_r8:
        movdqa  xmm0, XMMWORD [edx+0*SIZEOF_XMMWORD]
        movdqa  xmm1, XMMWORD [esi+0*SIZEOF_XMMWORD]
        pxor    xmm2,xmm2
        pxor    xmm3,xmm3
        mov     ecx, SIZEOF_XMMWORD
        jmp     short .downsample
        alignx  16,7

.columnloop:
        movdqa  xmm0, XMMWORD [edx+0*SIZEOF_XMMWORD]
        movdqa  xmm1, XMMWORD [esi+0*SIZEOF_XMMWORD]
        movdqa  xmm2, XMMWORD [edx+1*SIZEOF_XMMWORD]
        movdqa  xmm3, XMMWORD [esi+1*SIZEOF_XMMWORD]

.downsample:
        movdqa  xmm4,xmm0
        movdqa  xmm5,xmm1
        pand    xmm0,xmm6
        psrlw   xmm4,BYTE_BIT
        pand    xmm1,xmm6
        psrlw   xmm5,BYTE_BIT
        paddw   xmm0,xmm4
        paddw   xmm1,xmm5

        movdqa  xmm4,xmm2
        movdqa  xmm5,xmm3
        pand    xmm2,xmm6
        psrlw   xmm4,BYTE_BIT
        pand    xmm3,xmm6
        psrlw   xmm5,BYTE_BIT
        paddw   xmm2,xmm4
        paddw   xmm3,xmm5

        paddw   xmm0,xmm1
        paddw   xmm2,xmm3
        paddw   xmm0,xmm7
        paddw   xmm2,xmm7
        psrlw   xmm0,2
        psrlw   xmm2,2

        packuswb xmm0,xmm2

        movdqa  XMMWORD [edi+0*SIZEOF_XMMWORD], xmm0

        sub     ecx, byte SIZEOF_XMMWORD        ; outcol
        add     edx, byte 2*SIZEOF_XMMWORD      ; inptr0
        add     esi, byte 2*SIZEOF_XMMWORD      ; inptr1
        add     edi, byte 1*SIZEOF_XMMWORD      ; outptr
        cmp     ecx, byte SIZEOF_XMMWORD
        jae     near .columnloop
        test    ecx,ecx
        jnz     near .columnloop_r8

        pop     esi
        pop     edi
        pop     ecx

        add     esi, byte 2*SIZEOF_JSAMPROW     ; input_data
        add     edi, byte 1*SIZEOF_JSAMPROW     ; output_data
        dec     eax                             ; rowctr
        jg      near .rowloop

.return:
        pop     edi
        pop     esi
;       pop     edx             ; need not be preserved
;       pop     ecx             ; need not be preserved
;       pop     ebx             ; unused
        pop     ebp
        ret

; For some reason, the OS X linker does not honor the request to align the
; segment unless we do this.
        align   16
