; Minimal script to support changing profiles on secondary ESC(s)
; Please install main-esc.lisp on the primary ESC
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

@const-start

(defun main () {
        (sleep 2)
        (canmsg-recv 0 0.1)
        (canmsg-recv 0 0.1)
        (canmsg-recv 0 0.1)
        (start-code-server)
})

(image-save)
(main)
