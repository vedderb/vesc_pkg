# Midi Parser

This library is a wrapper for the midi-parser here
[https://github.com/abique/midi-parser](https://github.com/abique/midi-parser)

When loaded, the following extensions are provided

#### ext-midi-init

```clj
(ext-midi-init num-parsers)
```

Load library and allocate memory for num-parsers parsers that can run simultaneously on different files.

---

#### ext-midi-open

```clj
(ext-midi-open parser-num file)
```

Open midi-file file on parser parser-num.

#### ext-midi-parse

```clj
(ext-midi-parse parser-num)
```

Parse next available block on parser-num. Returns one of the following lists:

```clj
(midi-eob)
(midi-error)
(midi-init)
(midi-header size format tracks time-dif)
(midi-track size)
(midi-track-midi vtime status channel param1 param2)
(midi-track-meta vtime type length data)
(midi-track-sysex vtime)
```

---

## Example

```clj
(import "pkg::midi@://vesc_packages/lib_midi/midi.vescpkg" 'midi)
(import "pkg::midi_axelf_base@://vesc_packages/lib_files/files.vescpkg" 'axelf-base)
(import "pkg::midi_axelf_melody@://vesc_packages/lib_files/files.vescpkg" 'axelf-melody)

(load-native-lib midi)

(ext-midi-init 2)
(ext-midi-open 0 axelf-melody)
(ext-midi-open 1 axelf-base)

(foc-play-stop)

; Channel format (ch note freq vol decay)
; Note 0 means nothing is playing
(def num-chan 4)
(def channels (map (fn (x) (list x 0 0 0 0)) (range num-chan)))

(defun note-on (note vol decay)
    (atomic (loopforeach ch channels {
                (if (= (ix ch 1) 0) {
                        (var freq (* 440.0 (pow 2.0 (/ (- note 69.0) 12.0))))
                        (setix ch 2 freq)
                        (setix ch 3 vol)
                        (setix ch 4 decay)
                        (setix ch 1 note)
                        (foc-play-tone (ix ch 0) freq vol)
                        (break)
                })
})))

(defun note-off (note)
    (atomic (loopforeach ch channels {
                (if (= (ix ch 1) note) {
                        (setix ch 1 0)
                        (foc-play-tone (ix ch 0) 500 0)
                        (break)
                })
})))

; Exponential decay on active channels
(loopwhile-thd 200 t {
        (loopforeach ch channels
            (atomic (if (not (= (ix ch 1) 0)) {
                        (var ch-ind (ix ch 0))
                        (var freq (ix ch 2))
                        (var vol (ix ch 3))
                        (var decay (ix ch 4))
                        (setix ch 3 (* vol decay))
                        (foc-play-tone ch-ind freq vol)
        })))
        (sleep 0.02)
})

(def t-start (systime))

(defun play-midi (parser volts decay) {
        (var t-delta 0.0)
        (var midi-tdiv 100)
        (var midi-tempo 400000)
        
        (loopwhile t (match (ext-midi-parse parser)
                ((midi-header (? size) (? format) (? tracks) (? time-div)) {
                        (setq midi-tdiv time-div)
                })
                
                ((midi-track-midi (? time) (? status) (? chan) (? p1) (? p2)) {
                        (var secs (/ (* midi-tempo (to-float time)) midi-tdiv 1000000.0))
                        (setq t-delta (+ t-delta secs))
                        
                        (var to-sleep (- t-delta (secs-since t-start)))
                        (if (> to-sleep 0.001) (sleep to-sleep))
                        
                        ; Note on
                        (if (= status 9) {
                                (note-on p1 volts decay)
                        })
                        
                        ; Note off
                        (if (= status 8) {
                                (note-off p1)
                        })
                })
                
                ((midi-track-meta (? time) (? type) (? len) (? data)) {
                        ; Tempo
                        (if (= type 81)
                            (setq midi-tempo data)
                        )
                })
                
                (midi-error {
                        (print "Midi error")
                        (break)
                })
                
                (midi-eob {
                        (print "End of file")
                        (break)
                })
                
                ((? a) {
                        (print a)
                })
            )
)})

(spawn 200 play-midi 0 0.7 0.92)
(spawn 200 play-midi 1 0.4 0.92)
```
