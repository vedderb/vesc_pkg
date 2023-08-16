;@const-symbol-strings
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
    (spawn 50 (fn () {
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
        (canmsg-send id 0 (flatten (list (can-local-id) code)))
        (match (canmsg-recv 1 tout)
            (timeout timeout)
            ((? a) (unflatten a))
        )
})

(defun rcode-run-noret (id code) {
        (canmsg-send id 0 (flatten (list -1 code)))
})

 @const-end