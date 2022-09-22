# WS2812 Library

This is a library for driving WS2812 and similar addressable LEDs. You can use it from your LispBM-scripts by importing it and loading it as a native library:

```clj
(import "pkg::ws2812@://vesc_packages/lib_ws2812/ws2812.vescpkg" 'ws2812)
(load-native-lib ws2812)
```

That will give you the following extensions

```clj
(ext-ws2812-init led-num use-ch2 use-tim4 is-rgbw)
(ext-ws2812-set-color index colorRgb)
(ext-ws2812-set-brightness brightness)
```

The library uses timer 3 or timer 4 channel 1 or channel 2, meaning that you have 4 pins to choose from. On most hardwares hall 1 and hall 2 are channel 1 and channel 2 on timer 3 or timer 4, but you have to check the hwconf-file or schematic to make sure. To connect the LEDs you have to use a 1k pull-up resistor on that pin to 5v and connect it to the data input of the LEDs.

## Example

This is a complete, hopefully self-explanatory, example on how to import the library, configure it and run a demo on the LEDs. You can copy and paste it into the lisp editor and give it a try.

```clj
(import "pkg::ws2812@://vesc_packages/lib_ws2812/ws2812.vescpkg" 'ws2812)

(load-native-lib ws2812)

(def led-num 10)

(let (
    (use-ch2 0) ; 0 means CH1
    (use-tim4 0) ; 0 means TIM3
    (is-rgbw 1)) ; Some adressable LEDs have an extra white channel. Set this to 1 to use it
        (ext-ws2812-init led-num use-ch2 use-tim4 is-rgbw)
)

(def colors '(
    0x00550000i32
    0x00005500i32
    0x00000055i32
    0x55000000i32
))

(loopwhile t
    (loopforeach c colors
        (looprange i 0 led-num
            (progn
                (ext-ws2812-set-color (if (= i 0) (- led-num 1) (- i 1)) 0)
                (ext-ws2812-set-color i c)
                (sleep 0.02)
))))
```