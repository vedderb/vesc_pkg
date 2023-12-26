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

(def midi-tdiv 100)
(def midi-tempo 400000)

(foc-play-stop)

(def t-start (systime))

(defun play-on-ch (ch volts decay) {
        (var t-delta 0.0)
        (var volts-now 0.0)
        (var freq-now 1000.0)
        
        (loopwhile t (match (ext-midi-parse ch)
                ((midi-header (? size) (? format) (? tracks) (? time-div)) {
                        (setq midi-tdiv time-div)
                })
                
                ((midi-track-midi (? time) (? status) (? chan) (? p1) (? p2)) {
                        (var secs (/ (* midi-tempo (to-float time)) midi-tdiv 1000000.0))
                        (setq t-delta (+ t-delta secs))
                        
                        (loopwhile (> t-delta (secs-since t-start)) {
                                (sleep 0.001)
                                (setq volts-now (* volts-now decay))
                                (foc-play-tone ch freq-now volts-now)
                        })
                        
                        ; Note on
                        (if (= status 9) {
                                (var freq (* 440.0 (pow 2.0 (/ (- p1 69.0) 12.0))))
                                (setq volts-now volts)
                                (setq freq-now freq)
                                (foc-play-tone ch freq volts)
                        })
                        
                        ; Note off
                        (if (= status 8) {
                                (foc-play-tone ch 500 0.0)
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

(spawn 200 play-on-ch 0 0.7 0.995)
(spawn 200 play-on-ch 1 0.4 0.997)
```
