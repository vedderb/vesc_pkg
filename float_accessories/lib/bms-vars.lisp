;@const-symbol-strings

;const
(def key-crc '(3141361152u32))  ;AES-128 key. Offset in 6109: 0x12009
(def counter-crc '(4092889840u32)) ;IV for counter. Offset in 6109: 0x12019

(def key (bufcreate 16))
(def counter (bufcreate 16))
(def magic [0xff 0x55 0x00])

@const-start

(def bms-user-cmd -1)
(def bms-loop-delay)
(def bms-rs485-di-pin)
(def bms-rs485-ro-pin)
(def bms-rs485-dere-pin)
(def bms-wakeup-pin)
(def bms-use-crypto)
(def bms-override-soc 0)
(def bms-type 0)
(def bms-rs485-chip 0)
(def bms-charge-only 0)

;vars
(def cell-count-uninit t)
(def factory -1);TODO Check if bms is in factory mode somehow and init if is. Probably have a timer at boot looking for packets to determine valid state when connected.
(def is-charging -1)
(def is-current-over-limit -1)
(def is-battery-empty -1)
(def is-battery-temp-out-of-range -1)
(def is-battery-overcharged -1)
(def serial -1)

@const-end
