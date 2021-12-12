; vim: ft=nasm

global _start

struc sigaction
    .sa_handler  resq 1
    .sa_flags    resq 1
    .sa_restorer resq 1
    .sa_mask     resq 1
endstruc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; hardcoded from a getaddrinfo() call (see: test.c)
;                              ;; 0.0.0.0 ;;
addr: db 0x02, 0x00, 0x00, 0x50, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; our address
addr_len equ 0x10

sockopt_yes: dd 1
sockopt_yes_len: dd $ - sockopt_yes

server_fd: dq 0 ; current server fd
client_fd: dq 0 ; current client fd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .bss
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

peer: resb 0x80 ; current peer
peer_len: resd 1 ; current peer length

recv_buf: resb 0x400
recv_buf_len equ 0x400

sigact resb sigaction_size

file_buf: resb 0x400
file_buf_len equ 0x400

st_buf: resb 0x90 ; you might have to change this, see: test.c (specifically: struct st size)

; CWD + {http gotten path}
path_buf: resb PATH_MAX + recv_buf_len ; good enough
cwd_len: resq 1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .text
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; parameters
;  rdi: exit code
exit:
	mov rax, 60 ; sys_exit
	syscall
	ret

; parameters
;  rdi: buf
;  rsi: size
getcwd:
	mov rax, 79 ; sys_getcwd
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: dirent
;  rdx: count
getdents64:
	mov rax, 217 ; sys_getdents64
	syscall
	ret

rt_sigaction:
	mov rax, 13 ; sys_rt_sigaction
	syscall
	ret

rt_sigreturn:
	mov rax, 15 ; sys_rt_sigreturn
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: buf
;  rdx: count
read:
	mov rax, 0
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: buf
;  rdx: count
write:
	mov rax, 1 ; sys_write
	syscall
	ret

; parameters
;  rdi: filename (NULL-terminated)
;  rsi: flags
;  rdx: mode
open:
	mov rax, 2 ; sys_open
	syscall
	ret

; parameters
;  rdi: file name (NULL-terminated)
;  rsi: statbuf
stat:
	mov rax, 4 ; sys_newstat
	syscall
	ret

; parameters
;  rdi: family, AF_*
;  rsi: type,  SOCK_*
;  rdx: protocol, PF_*
; returns
;  rax: fd or errno
socket:
	mov rax, 41 ; sys_socket
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: (struc sockaddr) myaddr
;  rdx: addrlen
bind:
	mov rax, 49 ; sys_bind
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: backlog
listen:
	mov rax, 50 ; sys_listen
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: (struc sockaddr) peer
;  rdx: socklen
accept:
	mov rax, 43 ; sys_accept
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: buf
;  rdx: buf_len
;  r10: flags
;  r8:  addr
;  r9:  addr_len
recvfrom:
	mov rax, 45 ; sys_recvfrom
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: level
;  rdx: optname
;  r10: optval
;  r8:  optlen
setsockopt:
	mov rax, 54 ; sys_setsockopt
	syscall
	ret

; parameters
;  rdi: fd
close:
	mov rax, 3 ; sys_close
	syscall
	ret

; parameters
;  rdi: fd
;  rsi: i
write_int:
	mov r8, rdi ; fd is now in r8
	push word -1 ; indicator
	mov rcx, rsi

@@write_int_loop:
	mov rdx, 0    ;
	mov rax, rcx  ; rcx /
	mov rcx, 10   ;     / 10
	div rcx

	add dx, '0'
	push word dx ; push the next number

	mov rcx, rax ; setup for next iteration
	cmp rcx, 0
	jne @@write_int_loop
;; /@@write_int_loop

	mov rdi, r8 ; fd

@@write_int_loop2:
	; rdi still contains our fd
	mov word si, [rsp]
	mov rsi, rsp ; the top of the stack contains the char we need to write
	mov rdx, 1
	call write
	call chk_errno

	add rsp, 2 ; sizeof(dx) = 2; move to next int
	cmp word [rsp], -1 ; test for indicator
	jne @@write_int_loop2
;; /@@write_int_loop2
	add rsp, 2 ; remove indicator from stack

	ret

; parameters
;  rax: errno
errno_fail:
	cmp rax, 0
	jg @@print

	; remove sign if errno < 0,
	; which happens if rax is
	; passed directly from a syscall
	neg rax

@@print:
	push rax ; push errno

	mov rdi, FD_STDOUT
	mov rsi, fail_errno_msg_base
	mov rdx, fail_errno_msg_base_len
	call write

	mov rdi, FD_STDOUT
	pop rsi ; pop errno
	call write_int

	mov rdi, FD_STDOUT
	mov rsi, fail_errno_msg_end
	mov rdx, fail_errno_msg_end_len
	call write

	mov rdi, 1
	call exit
	ret

; parameters
;  rax: errno
chk_errno:
	cmp rax, 0
	jl errno_fail
	ret

; Sets the port of [addr]
; parameters
;   dx: port
set_port:
	; i though there was a bswap instruction?
	mov byte [addr + 0x2], dh
	mov byte [addr + 0x3], dl
	ret

terminate_server:
	mov rdi, [client_fd]
	cmp rdi, 0
	je @@terminate_server_check_server
	call close ; close the fd in rdi
	mov qword [client_fd], 0 ; don't want to close twice accidently
@@terminate_server_check_server:
	mov rdi, [server_fd]
	cmp rdi, 0
	je @@terminate_server_done
	call close ; close the fd in rdi
	mov qword [server_fd], 0 ; don't want to close twice accidently
@@terminate_server_done:
	ret

; parameters
;  rdi: file_len
serve_http_header:
	push rdi ; file_len

	mov rdi, [client_fd]
	mov rsi, http_header
	mov rdx, http_header_len
	call write ; "HTTP/1.1 200 Ok\r\nContent-Length: "
	call chk_errno

	mov rdi, [client_fd]
	pop rsi ; file_len
	call write_int ; {file_length}

	mov rdi, [client_fd]
	mov rsi, crlf2x
	mov rdx, crlf2x_len
	call write ; "\r\n\r\n"
	call chk_errno

	ret

; parameters
;  rdi: file name (NULL-terminated)
serve_file:
	; rdi already contains filename
	mov rsi, O_RDONLY
	mov rdx, 0 ; we don't need perms
	call open ; open file
	call chk_errno

	; file fd in stack
	push rax

@@serve_file_rw:
	mov rdi, [rsp] ; fd in rdi
	mov rsi, file_buf
	mov rdx, file_buf_len
	call read
	call chk_errno

	cmp rax, 0
	jle @@serve_file_end

	mov rdi, [client_fd]
	mov rsi, file_buf
	mov rdx, rax
	call write

	jmp @@serve_file_rw

@@serve_file_end:
	pop rdi ; pop fd
	call close

	ret

; parameters
;  rdi: dir name (NULL-terminated)
serve_dir:
	; rdi already has the dirname
	mov rsi, O_RDONLY
	mov rdx, 0 ; we don't need perms
	call open
	call chk_errno

	mov r10, rax
	xor rdx, rdx ;rdx=0

	mov r9, rsp ; save original rsp
@@serve_dir_readmore:
	sub rsp, 1000
	add rdx, 1000
	mov rsi, rsp
	mov rdi, r10
	call getdents64

	cmp rax, EINVAL ;EINVAL means buffer too small
	je @@serve_dir_readmore
	cmp rax, 0
	jle @@serve_dir_end

	mov r12, rsp
	push qword rax

	mov rcx, 10
	mul rcx ; should be enough

	mov r15, rsp
	sub r15, rax
	sub r15, rcx
	sub r15, serve_dir_body_end_len
	sub r15, serve_dir_body_start_len
	mov r14, r15

	pop qword r11 ;r11=read count

	mov rdi, r15
	mov rsi, serve_dir_body_start
	mov rdx, serve_dir_body_start_len
	call strcpy
	add r15, serve_dir_body_start_len

	lea rdi, [recv_buf+4] ; strlen("GET ") = 4
	mov rsi, recv_buf_len
	sub rsi, 4 ; we removed some bytes
	mov dl, ' ' ; we want to find the next space
	call strfind
	; now we have the path len ("/hello/world")
	; but we just want ("/hello") so we need to rfind
	mov rsi, rax
	call dirname
	cmp rax, -1
	jne @@serve_dir_after_rfind
	mov rax, rsi
@@serve_dir_after_rfind:
	mov rdi, r15
	lea rsi, [recv_buf+4]
	mov rdx, rax
	call strcpy
	add r15, rdx

	mov rdi, r15
	mov rsi, serve_dir_body_start2
	mov rdx, serve_dir_body_start2_len
	call strcpy
	add r15, serve_dir_body_start2_len

	; the amount of dirs read is in rax, we
	; can read from the stack

@@serve_dir_iter:
	mov r13, rsp
	sub r13, r12
	cmp r13, r11
	jge @@serve_dir_end ;; TODO: make this loop work ;;

;	cmp dword [rsp+16], 0 ; is d_reclen=0?
;	je @@serve_dir_end
;	dec r12

	lea rdi, [rsp+19]
	mov rsi, dot
	mov rdx, dot_len
	call cmp_str ; check for "."
	je @@serve_dir_iter_jmp

	mov rdi, r15
	mov rsi, dirent_start1
	mov rdx, dirent_start1_len
	call strcpy
	add r15, dirent_start1_len

	lea rdi, [recv_buf+4] ; strlen("GET ") = 4
	mov rsi, recv_buf_len
	sub rsi, 4 ; we removed some bytes
	mov dl, ' ' ; we want to find the next space
	call strfind
	mov rdi, r15
	lea rsi, [recv_buf+4]
	mov rdx, rax
	call strcpy
	add r15, rdx

	cmp rdx, 1 ; check if length(path) == 1
	           ; if yes it can only be "/"
	je @@serve_dir_iter_fname

	mov rdi, r15
	mov rsi, slash
	mov rdx, slash_len
	call strcpy
	add r15, slash_len

@@serve_dir_iter_fname:
	lea rdi, [rsp+19]
	call strlen
	mov rsi, rdi
	mov rdx, rax
	mov rdi, r15
	call strcpy
	add r15, rdx

	mov rdi, r15
	mov rsi, dirent_start2
	mov rdx, dirent_start2_len
	call strcpy
	add r15, dirent_start2_len

	lea rdi, [rsp+19]
	call strlen
	mov rsi, rdi
	mov rdx, rax
	mov rdi, r15
	call strcpy
	add r15, rdx

	; check if we need to append a '/' for a directory
	cmp byte [rsp+18], DT_DIR
	je @@serve_dir_style_dir

	; check if we need to append an '@' for a link
	cmp byte [rsp+18], DT_LNK
	je @@serve_dir_style_link

	; no style needed
	jmp @@serve_dir_end_style

@@serve_dir_style_dir:
	; write a '/'
	mov rdi, r15
	mov rsi, slash
	mov rdx, slash_len
	call strcpy
	add r15, slash_len
	jmp @@serve_dir_end_style

@@serve_dir_style_link:
	; write an '@'
	mov rdi, r15
	mov rsi, at_sym
	mov rdx, at_sym_len
	call strcpy
	add r15, at_sym_len
	jmp @@serve_dir_end_style

@@serve_dir_end_style:
	mov rdi, r15
	mov rsi, dirent_end
	mov rdx, dirent_end_len
	call strcpy
	add r15, rdx

@@serve_dir_iter_jmp:
	add sp, [rsp+16]
	jmp @@serve_dir_iter
@@serve_dir_end:

	mov rdi, r15
	mov rsi, serve_dir_body_end
	mov rdx, serve_dir_body_end_len
	call strcpy
	add r15, serve_dir_body_end_len

	mov rdi, [client_fd]
	mov rsi, serve_dir_begin
	mov rdx, serve_dir_begin_len
	call write
	call chk_errno

	mov rdi, [client_fd]
	mov rsi, r15
	sub rsi, r14 ; body length, r14 = body buf start
	call write_int

	mov rdi, [client_fd]
	mov rsi, serve_dir_begin2
	mov rdx, serve_dir_begin2_len
	call write
	call chk_errno

	mov rdi, [client_fd]
	mov rsi, r14
	mov rdx, r15
	sub rdx, r14 ; body length, r14 = body buf start
	call write
	call chk_errno

	mov rdi, [client_fd]
	mov rsi, serve_dir_body_end
	mov rdx, serve_dir_body_end_len
	call write
	call chk_errno

	;; very close!! soon be done <3 ;;

	mov rsp, r9 ; restore original rsp
	ret

; parameters
;  rdi: file name (NULL-terminated)
;  rsi: file length
complete_serve_file:
	;; TODO: Find Content-Type? ;;
	push rsi
	push rdi
	mov rdi, rsi
	call serve_http_header
	pop rdi
	pop rsi
	call serve_file
	ret

; parameters
;  rdi: str_a
;  rsi: str_b
;  rdx: str_b_size
; note
;  if length(str_a) != length(str_b) then
;   it will only compare the first str_b_size bytes of str_a/b
cmp_str:
	xor rax, rax ; rax=0
@@cmp_str_iter:
	mov ch, [rdi+rax]
	mov cl, [rsi+rax]
	cmp byte ch, cl; are str_a[i] and str_b[i] equal?
	jne @@cmp_str_end
	inc rax ; ++i
	cmp rax, rdx ; are we at the end?
	jne @@cmp_str_iter
@@cmp_str_end:
	ret

; parameters
;  rdi: string
; returns
;  rax: string length
strlen:
	xor rax, rax ; rax=0
@@strlen_iter:
	cmp byte [rdi+rax], 0 ; end of string?
	je @@strlen_end
	inc rax ; ++i
	jmp @@strlen_iter
@@strlen_end:
	ret

; parameters
;  rdi: retstring
;  rsi: string
;  rdx: string_len
strcpy:
	xor rax, rax ; rax=0
@@strcpy_iter:
	cmp rax, rdx
	je @@strcpy_end
	mov cl, [rsi+rax]
	mov [rdi+rax], cl
	inc rax
	jmp @@strcpy_iter
@@strcpy_end:
	; add null-term
	mov byte [rdi+rax], 0
	ret

; parameters
;  rdi: string (NULL-terminated)
; returns
;  rax: amount of directories this goes down relative to the string
;        (/../ returns 1, /../.. returns 2, etc), negative if it goes up
;        (/hello/ returns -1, /hello/2 returns -2, etc)
count_dir_down:
	xor rax, rax
	xor rcx, rcx
@@count_dir_down_iter:
	cmp byte [rdi+rcx], 0
	je @@count_dir_down_end

	cmp byte [rdi+rcx], '/'
	je @@count_dir_down_slash

	inc rcx
	jmp @@count_dir_down_iter
@@count_dir_down_slash:
	dec rax
	inc rcx

	cmp byte [rdi+rcx], 0
	je @@count_dir_down_end
	cmp byte [rdi+rcx+1], 0
	je @@count_dir_down_end

	; check for ../ | ..\0
	cmp byte [rdi+rcx+0], '.' ;    /.
	jne @@count_dir_down_slash_end
	cmp byte [rdi+rcx+1], '.' ;    /..
	jne @@count_dir_down_slash_end
	cmp byte [rdi+rcx+2], '/' ;    /../
	je @@count_dir_down_double_dot
	cmp byte [rdi+rcx+2], 0   ;    /..\0
	jne @@count_dir_down_slash_end

@@count_dir_down_double_dot:
	inc rax ; we did find a ..
	add rcx, 3

@@count_dir_down_slash_end:
	jmp @@count_dir_down_iter
;; /@@count_dir_down_slash
@@count_dir_down_end:
	cmp rcx, 0 ; 0-length string
	je @@count_dir_down_final
	cmp byte [rdi+rcx-1], '/'
	jne @@count_dir_down_final
	; trailing slash doesn't count
	inc rax
@@count_dir_down_final:
	ret

; parameters
;  rdi: string
;  rsi: string_len
;  dl: character
; returns
;  rax: index or -1
strfind:
	xor rax, rax ; rax=0
@@strfind_iter:
	cmp rax, rsi
	je @@strfind_no_match
	cmp [rdi+rax], dl
	je @@strfind_end
	inc rax
	jmp @@strfind_iter
@@strfind_no_match:
	mov rax, -1
@@strfind_end:
	ret

; parameters
;  rdi: string
;  rsi: string_len
;  dl: character
; returns
;  rax: index or -1
strrfind:
	lea rax, [rsi-1]
@@strrfind_iter:
	cmp [rdi+rax], dl
	je @@strrfind_end
	cmp rax, 0
	je @@strrfind_no_match
	dec rax
	jmp @@strrfind_iter
@@strrfind_no_match:
	mov rax, -1
@@strrfind_end:
	ret

; parameters
;  rdi: string
;  rsi: string_len
; returns
;  rax: index or -1
; spoils
;  rsi
dirname:
	lea rax, [rsi-1]
@@dirname_remove_trail:
	cmp byte [rdi+rax], '/'
	jne @@dirname_continue
	cmp rax, 0
	je @@dirname_fail
	dec rax
	jmp @@dirname_remove_trail
@@dirname_continue:
	mov rsi, rax
	mov dl, '/'
	call strrfind
	jmp @@dirname_end
@@dirname_fail:
	mov rax, -1
@@dirname_end:
	ret

sigint_handler:
	mov rdi, FD_STDOUT
	mov rsi, terminated_msg
	mov rdx, terminated_msg_len
	call write
	call terminate_server
	ret

sigrestorer:
	mov rdi, 0
	call exit
	ret

setup_signals:
	mov qword [sigact + sigaction.sa_handler], sigint_handler
	mov dword [sigact + sigaction.sa_flags], SA_RESTORER
	mov qword [sigact + sigaction.sa_restorer], sigrestorer
	mov dword [sigact + sigaction.sa_mask], 0

	mov rdi, SIGINT
	mov rsi, sigact
	mov rdx, 0x0 ; (NULL)
	mov r10, 0x8
	call rt_sigaction
	call chk_errno
	ret

_start:
main:
	call setup_signals

	; get cwd
	mov rdi, path_buf
	mov rsi, PATH_MAX
	call getcwd
	call strlen ; rdi=path_buf=getcwd()
	mov [cwd_len], rax

	mov rdi, PF_INET
	mov rsi, SOCK_STREAM
	mov rdx, AF_UNSPEC
	call socket
	call chk_errno

	; rax now contains our fd socket fd

	mov rdi, rax
	mov rsi, SOL_SOCKET
	mov rdx, SO_REUSEADDR
	mov r10, sockopt_yes
	mov r8, sockopt_yes_len
	call setsockopt ; re-use addr
	call chk_errno

	mov dx, 8000
	call set_port

	mov rsi, addr
	mov rdx, addr_len
	call bind
	call chk_errno

	mov rsi, 10 ; backlog=10
	call listen ; rdi is still our fd
	call chk_errno

	mov [server_fd], rdi

@@accept_loop:
	mov rdi, [server_fd]
	mov rsi, peer
	mov rdx, peer_len
	call accept
	call chk_errno

	mov [client_fd], rax

	;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; now we do http stuff ;;
	;;;;;;;;;;;;;;;;;;;;;;;;;;

	mov rdi, [client_fd]
	mov rsi, recv_buf
	mov rdx, recv_buf_len
	mov r10, 0
	mov r8, peer
	mov r9, peer_len
	call recvfrom
	call chk_errno

	; parse the body

	cmp rdi, 0 ; if the size is 0 we're done with this client
	je @@fd_done

	mov rdi, recv_buf
	mov rsi, GET_req
	mov rdx, GET_req_len
	call cmp_str
	jne @@fd_bad_req ; not GET? => 400 bad request

	lea rdi, [recv_buf+4] ; strlen("GET ") = 4
	mov rsi, recv_buf_len
	sub rsi, 4 ; we removed some bytes
	mov dl, ' ' ; we want to find the next space
	call strfind
	cmp rax, -1
	je @@fd_bad_req

	lea rsi, [recv_buf+4]
	cmp byte [rsi], '/'; first char of http path must be /
	jne @@fd_bad_req

	mov rdi, path_buf
	add rdi, [cwd_len]
	lea rsi, [recv_buf+4]
	mov rdx, rax
	call strcpy

	; check if we aren't breaking out of cwd
	;; TODO ;; actually make it work
	call count_dir_down
	cmp rax, 0
	jle @@fd_stat_file

	; we redirect to / if we are
	mov byte [rdi+1], 0

@@fd_stat_file:
	mov rdi, path_buf
	mov rsi, st_buf
	call stat
	cmp rax, -2 ; ENOENT
	je @@fd_bad_404
	cmp rax, 0
	jl @@fd_bad_500 ; internal server error

	; test if we're looking at a dir
	mov dword ecx, [st_buf + 0x18] ; you might have to change this, see: test.c (specifically: st.st_mode offset)
	and dword ecx, S_IFDIR
	cmp dword ecx, 0
	jne @@fd_serve_dir

	; rdi still has path_buf
	mov rsi, [st_buf + 0x30] ; you might have to change this, see: test.c (specifically: st.st_size offset)
	call complete_serve_file
	jmp @@fd_done

@@fd_serve_dir:
	mov rdi, path_buf
	call serve_dir
	jmp @@fd_done

@@fd_bad_req: ; bad request
	mov rdi, [client_fd]
	mov rsi, bad_req_400
	mov rdx, bad_req_400_len
	call write
	jmp @@fd_done

@@fd_bad_403: ; forbidden
@@fd_bad_404: ; not found
	mov rdi, [client_fd]
	mov rsi, bad_req_404
	mov rdx, bad_req_404_len
	call write
	jmp @@fd_done

@@fd_bad_500: ; internal server error
	mov rdi, [client_fd]
	mov rsi, bad_req_500
	mov rdx, bad_req_500_len
	call write
	jmp @@fd_done

@@fd_done:
	mov rdi, [client_fd]
	call close
	call chk_errno
	mov qword [client_fd], 0

	; infinite loop
	jmp @@accept_loop

@@http_end:
	call terminate_server
	xor rdi, rdi
	call exit

SOCK_STREAM equ 1
SOCK_DGRAM equ 2

AF_UNSPEC equ 0
AF_INET equ 2

PF_UNSPEC equ AF_UNSPEC
PF_INET equ AF_INET

FD_STDOUT equ 1

SOL_SOCKET equ 1
SO_REUSEADDR equ 2

SIGINT equ 0x2

SA_RESTORER equ 0x4000000

O_RDONLY equ 00

PATH_MAX equ 4096

S_IFDIR equ 0x4000

DT_DIR equ 4
DT_LNK equ 10

EINVAL equ -22

fail_errno_msg_base: db "# syscall failed", 0x0a, "errno "
fail_errno_msg_base_len equ $ - fail_errno_msg_base

fail_errno_msg_end: db 0x0a
fail_errno_msg_end_len equ $ - fail_errno_msg_end

terminated_msg: db "Terminated. Shutting down server.", 0x0a
terminated_msg_len equ $ - terminated_msg

http_header: db "HTTP/1.1 200 Ok", 0x0d, 0x0a, "Content-Length: "
http_header_len equ $ - http_header

http_header_html: db "HTTP/1.1 200 Ok", 0x0d, 0x0a, "Content-Type: text/html", 0x0d, 0x0a, "Content-Length: "
http_header_html_len equ $ - http_header_html

crlf2x: db 0x0d, 0x0a, 0x0d, 0x0a
crlf2x_len equ $ - crlf2x

GET_req: db "GET "
GET_req_len equ $ - GET_req

bad_req_400: db "HTTP/1.1 400 Bad Request", 0x0d, 0x0a, "Content-Type: text/html", 0x0d, 0x0a, "Content-Length: 156", 0x0d, 0x0a, 0x0d, 0x0a, "<!DOCTYPE html><html><body><center><p>400 - Bad Request</p></center><hr/><center><p>Your browser (is it?) sent an invalid request</p></center></body></html>"
bad_req_400_len equ $ - bad_req_400

bad_req_404: db "HTTP/1.1 404 Not Found", 0x0d, 0x0a, "Content-Type: text/html", 0x0d, 0x0a, "Content-Length: 150", 0x0d, 0x0a, 0x0d, 0x0a, "<!DOCTYPE html><html><body><center><p>404 - Not Found</p></center><hr/><center><p>The requested resource could not be found</p></center></body></html>"
bad_req_404_len equ $ - bad_req_404

bad_req_500: db "HTTP/1.1 500 Internal Server Error", 0x0d, 0x0a, "Content-Type: text/html", 0x0d, 0x0a, "Content-Length: 152", 0x0d, 0x0a, 0x0d, 0x0a, "<!DOCTYPE html><html><body><center><p>500 - Internal Server Error</p></center><hr/><center><p>The server encountered an error</p></center></body></html>"
bad_req_500_len equ $ - bad_req_404

dirent_start1: db "<li><a href=", '"'
dirent_start1_len equ $ - dirent_start1

dirent_start2: db '"', ">"
dirent_start2_len equ $ - dirent_start2

dirent_end: db "</a></li>"
dirent_end_len equ $ - dirent_end

serve_dir_begin: db "HTTP/1.1 200 Ok", 0x0d, 0x0a, "Content-Type: text/html", 0x0d, 0x0a, "Content-Length: "
serve_dir_begin_len equ $ - serve_dir_begin

serve_dir_begin2: db 0x0d, 0x0a, 0x0d, 0x0a
serve_dir_begin2_len equ $ - serve_dir_begin2

serve_dir_body_start: db "<!DOCTYPE html><html><body><ul><li><a href=", '"'
serve_dir_body_start_len equ $ - serve_dir_body_start

serve_dir_body_start2: db "/", '"', ">(go up a directory)</a></li>"
serve_dir_body_start2_len equ $ - serve_dir_body_start2


serve_dir_body_end: db "</ul></body></html>"
serve_dir_body_end_len equ $ - serve_dir_body_end

dot: db "."
dot_len equ $ - dot

slash: db "/"
slash_len equ $ - slash

at_sym: db "@"
at_sym_len equ $ - at_sym

