@const-start

(defun view-init-minigame () {
    (def buf-game-over (img-buffer dm-pool 'indexed4 196 60))
    (def game-score 0)
    (def game-seconds 0)
    (def game-start-time (systime))

    (def bricks-row (range 0 10))
    (def bricks-row-y 42)
    (def bricks-height 8)
    (def buf-bricks (img-buffer dm-pool 'indexed2 320 10))

    (def game-over nil)
    (def ball-size 9)
    (def buf-ball (img-buffer dm-pool 'indexed2 (+ ball-size 1) (+ ball-size 1)))
    (def ball-x (mod (rand) 319))
    (def ball-x-rate 0.8)
    (def ball-y (+ bricks-row-y ball-size (mod (rand) 20)))
    (def ball-y-rate 1.0)
    
    (img-rectangle buf-ball 0 0 ball-size ball-size 1 `(rounded ,(- (/ ball-size 2) 1)) '(filled))

    (def buf-paddle (img-buffer dm-pool 'indexed2 320 10))
    (def paddle-x 0)
    (def paddle-y 200)
    (def paddle-width 40)

    (view-init-menu)
    (defun on-btn-0-pressed () {
        (if (> (- paddle-x 3) 0) (setq paddle-x (- paddle-x 3)))
    })
    (defun on-btn-0-repeat-press () {
        (if (> paddle-x 0) (setq paddle-x (- paddle-x 1)))
    })

    (defun on-btn-1-pressed () {
        ; Reset Game
        (disp-clear)
        (view-render-menu)
        (def game-over false)
        (def bricks-row (range 0 10))
        (def ball-x (mod (rand) 319))
        (def ball-x-rate 0.8)
        (def ball-y (+ bricks-row-y ball-size (mod (rand) 20)))
        (def ball-y-rate 1.0)
        (img-clear buf-game-over)
        (def game-score 0)
        (def game-start-time (systime))
    })
    (defun on-btn-2-pressed () {
        (def state-view-next 'view-main)
    })
    (defun on-btn-3-pressed () {
        (if (< (+ paddle-x paddle-width 3) 320) (setq paddle-x (+ paddle-x 3)))
    })
    (defun on-btn-3-repeat-press () {
        (if (< (+ paddle-x paddle-width) 320) (setq paddle-x (+ paddle-x 1)))
    })

    ; Render Menu
    (view-draw-menu 'arrow-left "RESET" "EXIT" 'arrow-right)
    (view-render-menu)
})

(defunret view-draw-minigame () {

    (if game-over {
        (txt-block-c buf-game-over (list 0 1 2 3) (/ (first (img-dims buf-game-over)) 2) 6 font15 (list
            (to-str "Game Over")
            (str-merge (str-from-n game-score "%d point") (if (not-eq game-score 1) "s" ""))
            (str-merge (str-from-n game-seconds "%d second") (if (not-eq game-seconds 1) "s" ""))
        ))
        (return)
    })

    ;; Handle Ball
    (def ball-x-old ball-x)
    (def ball-y-old ball-y)    
    (setq ball-x (+ ball-x ball-x-rate))
    (setq ball-y (+ ball-y ball-y-rate))
    

    ; Bounds check
    (if (or 
        (<= ball-x 2)
        (>= (+ ball-x ball-size) 318)
    ) (setq ball-x-rate (* ball-x-rate -1.0)))
    (if (< ball-y 1) (setq ball-y-rate (* ball-y-rate -1.0)))


    ; TODO menu height plus paddle hieight
    (if (> (+ ball-y ball-size) paddle-y) {
        (print "game over")
        (def game-over true)
        (def game-seconds (to-i (secs-since game-start-time)))
        (return)
        ;(setq ball-y-rate (* ball-y-rate -1.0))
    })

    ; Paddle detection
    ;if ball-y + ball-size >= paddle-y 
    ; & ball-x + 0.5 ball-size > paddle-x && < paddle-x + paddle-width
    (if (and (>= (+ ball-y ball-size) paddle-y)
            (and (> (+ ball-x (* 0.5 ball-size)) paddle-x) ; center of ball after paddle-x start
                 (< (+ ball-x (* 0.5 ball-size)) (+ paddle-x paddle-width)) ; center of ball before paddle-x + paddle-width
            )
        )
        {
            (var max-rate-x-abs 2)
            ; Adjust speed
            (if (< (abs ball-y-rate) 10) (setq ball-y-rate (+ ball-y-rate 0.2 )))
            ; Adjust direction
            (setq ball-y-rate (* ball-y-rate -1.0))

            ; Random angle
            ;(setq ball-x-rate (+ ball-x-rate (* (- (mod (rand) 200) 100) 0.01)))
            ; Set angle based on input angle vs paddle position
            ;
            ; Where did the ball touch?
            (var ball-x-touch-pos (+ ball-x (* 0.5 ball-size)))
            (var ball-paddle-pos (/ (- ball-x-touch-pos paddle-x) paddle-width))
            (print (list "ball hit x "  ball-x-touch-pos "paddle pos" paddle-x "calc" ball-paddle-pos))


            (setq ball-x-rate (* (- (* ball-paddle-pos 2) 1 ) (* ball-y-rate -1)))
            (print (list "xrate" ball-x-rate))
            
        }
    )

    ;; Handle paddle
    (img-clear buf-paddle)
    (img-rectangle buf-paddle paddle-x 0 paddle-width 8 1 '(rounded 3) '(filled)) ;(img-rectangle img x y width height color opt-attr1


    ;; Bricks Section
    (var brick-w 30)
    (var i 0)
    ;; Collision detect bricks
    (loopwhile (< i (length bricks-row)) {
        (if (not-eq (ix bricks-row i) nil) {
            ; Check if we are hitting this brick
            (var this-brick-x (+ (* i brick-w) (* i 2)))
            (var this-brick-x2 (+ this-brick-x brick-w))

            (var this-brick-y2 (+ bricks-row-y bricks-height))

            (if (and
                    (<= ball-y (+ bricks-row-y bricks-height)) ; ball top is above bottom of brick row
                    (>= (+ ball-y ball-size) bricks-row-y) ; ball bottom is below top of brick row
                    (>= (+ ball-x ball-size) this-brick-x); ball right is greater than right of brick
                    (<= ball-x this-brick-x2); ball left is less than left of brick
                ) {
                ; Ball hit brick, invert ball x and y rate
                (print (list "ball hit brick" i))

                (setq game-score (+ game-score 1)) ; +1 point

                (setix bricks-row i nil) ; Clear brick
                
                (setq ball-y-rate (* ball-y-rate -1.0)) ; Change up down direction
            })
        })
        (setq i (+ i 1))
    })

    ;; Draw brick row
    (setq i 0)
    (img-clear buf-bricks)
    (loopwhile (< i (length bricks-row)) {
        (if (not-eq (ix bricks-row i) nil) {
            ; Draw brick as pos i
            (img-rectangle buf-bricks (+ (* i brick-w) (* i 2)) 0 brick-w bricks-height 1 '(rounded 3) '(filled))
        })
        (setq i (+ i 1))
    })
})

(defun view-render-minigame () {
    (if (not game-over) {
        (disp-render buf-paddle 0 paddle-y '(0x000000 0xfbfcfc))

        (disp-render buf-bricks 0 bricks-row-y '(0x000000 0xfbfcfc))

        (disp-render buf-ball ball-x-old ball-y-old '(0x000000 0x000000)) ; Clear old position
        (disp-render buf-ball ball-x ball-y '(0x000000 0xfbfcfc))

        
    } (disp-render buf-game-over (- 160 (/ (first (img-dims buf-game-over)) 2)) (+ bricks-row-y 42) '(0x000000 0x4f514f 0x929491 0xfbfcfc)))
})

(defun view-cleanup-minigame () {
    (def buf-paddle nil)
    (def buf-game-over nil)
    (def buf-bricks nil)
    (def buf-ball nil)
})
