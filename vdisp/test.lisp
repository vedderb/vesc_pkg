(import "test-icon.bin" 'icon-l)
(def llama (img-buffer-from-bin icon-l))
(def img (img-buffer 'indexed4 (first (img-dims llama)) (second (img-dims llama))))

(def llama-dims (img-dims llama))
(def llama-w (first llama-dims))
(def llama-h (second llama-dims))

(img-blit img llama 10 10 -1)
(img-blit img llama 120 10 -1 `(rotate ,(/ llama-w 2) ,(/ llama-h 2) 45))
;(img-blit img llama 10 120 -1 '(scale 0.5))
;(img-blit img llama 120 120 -1 '(scale 1.5))
;(img-blit img llama 20 60 -1 '(scale 1.5) `(rotate ,(/ llama-w 2) ,(/ llama-h 2) 45))
