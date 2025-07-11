; Firmware 6.5 does not have mutexes
(if (eq (take (sysinfo 'fw-ver) 2) '(6 5)) {
        (defun mutex-create () nil)
        (defun mutex-lock (mtx) nil)
        (defun mutex-unlock (mtx) nil)
})

(def code-server-mutex (mutex-create))

@const-start

(defun code-server-worker (parent)
    (loopwhile t {
            (var rx (unflatten (canmsg-recv 0 -1)))
            (var id (first rx))

            (send parent (list 'can-id id))

            (if (>= id 0)
                (canmsg-send id 1 (flatten (eval (second rx))))
                (eval (second rx))
            )
}))

(defun start-code-server ()
    (spawn 150 (fn () {
                (var last-id 0)
                (var respawn true)

                (loopwhile t {
                        (if respawn {
                                (spawn-trap "CodeSrv" code-server-worker (self))
                                (setq respawn false)
                        })

                        (recv
                            ((exit-error (? tid) (? v)) {
                                    (setq respawn true)
                                    (if (>= last-id 0)
                                        (canmsg-send last-id 1 (flatten 'eerror))
                                    )
                            })

                            ((can-id (? id)) {
                                    (setq last-id id)
                            })
                        )
                })
})))

(defun rcode-run (id tout code) {
        (mutex-lock code-server-mutex)
        (canmsg-send id 0 (flatten (list (can-local-id) code)))
        (var res (match (canmsg-recv 1 tout)
                (timeout timeout)
                ((? a) (unflatten a))
        ))
        (mutex-unlock code-server-mutex)
        res
})

(defun rcode-run-noret (id code) {
        (mutex-lock code-server-mutex)
        (var res (canmsg-send id 0 (flatten (list -1 code))))
        (mutex-unlock code-server-mutex)
        res
})

@const-end
