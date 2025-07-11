; Minimal script to support changing profiles on secondary ESC(s)
; Please install main-esc.lisp on the primary ESC
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)
(start-code-server)
