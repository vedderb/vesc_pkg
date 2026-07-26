;@const-symbol-strings
@const-start

; Pubmote protocol constants. Load before the other pubmote files.

; Pairing states
(def PAIR_STATE_IDLE 0)
(def PAIR_STATE_INITIATED 1)
(def PAIR_STATE_BONDING 2)

; Vehicle types reported to the remote
(def VEHICLE_TYPE_UNSPECIFIED 0)
(def VEHICLE_TYPE_ONEWHEEL 1)
(def VEHICLE_TYPE_ESKATE 2)
(def VEHICLE_TYPE_SCOOTER 3)
(def VEHICLE_TYPE_EUC 4)

; Protocol commands
(def REM_VERSION 0)
(def REM_VERSION_REC 5)
(def REM_PAIR_INIT 10)
(def REM_PAIR_BOND 11)
(def REM_PAIR_COMPLETE 12)
(def REM_SET_CORE_DATA 100)
(def REM_SET_INPUT_STATE 150)
(def PUBMOTE_MAGIC 169)

@const-end
