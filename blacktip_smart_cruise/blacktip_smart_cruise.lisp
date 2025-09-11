;****Section to set initial settings ****

; User speeds, ie 1 thru 8 are only used in the GUI, this lisp code uses speeds 0-9 with 0 & 1 being the 2 revese speeds. 
; 99 is used as the "off" speed

(if (not-eq (eeprom-read-i 127) (to-i32 150)); check to see if slot 127 in eeprom is empty (or not current rev level 1.21 = 121) indicating new firmware and defaults have not been set
(progn
(eeprom-store-i 0 45); Reverse Speed 2 %
(eeprom-store-i 1 20); Untangle Speed 1 %
(eeprom-store-i 2 30); Speed 1 %
(eeprom-store-i 3 38); Speed 2 %
(eeprom-store-i 4 46); Speed 3 %
(eeprom-store-i 5 54); Speed 4 %
(eeprom-store-i 6 62); Speed 5 %
(eeprom-store-i 7 70); Speed 6 %
(eeprom-store-i 8 78); Speed 7 %
(eeprom-store-i 9 100); Speed 8 %
(eeprom-store-i 10 9) ; Maximum number of Speeds to use, must be greater or equal to Start_Speed (actual speed #, not user speed)
(eeprom-store-i 11 4) ; Speed the scooter starts in. Range 2-9, must be less or equal to the Max_Speed_No (actual speed #, not user speed)
(eeprom-store-i 12 7) ; Speed to jump to on triple click, (actual speed #, not user speed)
(eeprom-store-i 13 1) ; Turn safe start on or off 1=On 0=Off
(eeprom-store-i 14 0) ; Enable Reverse speed. 1=On 0=Off 
(eeprom-store-i 15 0) ; Enable 5 click Custom Control. 1=On 0=Off
(eeprom-store-i 16 1) ; How long before custom control times out and requires reactivation in min.
(eeprom-store-i 17 0) ; Rotation of Display, 0-3 . Each number rotates display 90 deg.
(eeprom-store-i 18 5) ; Display Brighness 0-5
(eeprom-store-i 19 0) ; Bluetooth Wiring, 0 = Blacktip HW60 + Ble, 1 = Blacktip HW60 - Ble, 2 = Blacktip HW410 - Ble, 3 = Cuda-X HW60 + Ble, 4 = Cuda-X HW60 - Ble
(eeprom-store-i 20 0) ; Battery Beeps
(eeprom-store-i 21 3) ; Beep Volume
(eeprom-store-i 22 0) ; CudaX Flip Screens
(eeprom-store-i 23 0) ; 2nd Screen Rotation of Display, 0-3 . Each number rotates display 90 deg. 
(eeprom-store-i 24 0) ; Trigger Click Beeps
(eeprom-store-i 127 150); writes 150 to eeprom to stop settings being loaded again
))

;**** Program to update settings from eeprom ****

(defun Update_Settings () ;Program that reads eeprom and writes to variables
   (progn

(define Max_Speed_No (eeprom-read-i 10))
(define Start_Speed (eeprom-read-i 11) )
(define Jump_Speed (eeprom-read-i 12))
(define Use_Safe_Start (eeprom-read-i 13))
(define Enable_Reverse (eeprom-read-i 14))
(define Enable_Custom_Control (eeprom-read-i 15)) 
(define Custom_Control_Timeout (eeprom-read-i 16))
(define Rotation (eeprom-read-i 17)) 
(define Disp_Brightness (eeprom-read-i 18)) 
(define Bluetooth (eeprom-read-i 19))
(define Enable_Battery_Beeps (eeprom-read-i 20))
(define Beeps_Vol (eeprom-read-i 21))
(define CudaX_Flip (eeprom-read-i 22))
(define Rotation2 (eeprom-read-i 23))
(define Enable_Trigger_Beeps (eeprom-read-i 24))

(define Speed_Set (list 
(eeprom-read-i 0); Reverse Speed 2 %
(eeprom-read-i 1); Untangle Speed 1 %
(eeprom-read-i 2); Speed 1 %
(eeprom-read-i 3); Speed 2 %
(eeprom-read-i 4); Speed 3 %
(eeprom-read-i 5); Speed 4 %
(eeprom-read-i 6); Speed 5 %
(eeprom-read-i 7); Speed 6 %
(eeprom-read-i 8); Speed 7 %
(eeprom-read-i 9); Speed 8 %
))

(if (<= Bluetooth 2) ; Sets scooter type, 0 = Blacktip, 1 = Cuda X
    (define Scooter_Type 0)
    (define Scooter_Type 1)
    ) 
))

(move-to-flash Update_Settings)

(Update_Settings) ; creates all settings variables   

;**** Program that interperets data from GUI ****

(defun My_Data_Recv_Prog (data)
   (progn
    (if (= (bufget-u8 data 0) 255 );Handshake to trigger data send if not yet recieved. 
    (progn
    
    (define setbuf (array-create 25))  ;create a temp array to store setinsg
    (bufclear setbuf) ;clear the buffer 
    (looprange i 0 25
    (bufset-i8 setbuf i (eeprom-read-i i)))
    (send-data setbuf)
    (free setbuf)
    )
    
    (progn
    (looprange i 0 25
    (eeprom-store-i i (bufget-u8 data i))); writes settings to eeprom 
    (Update_Settings); updates actuall settings in lisp
    
    )
)))

(move-to-flash My_Data_Recv_Prog)

;**** Programs that setup comms with GUI ****

(defun event-handler () 
   (progn
   (loopwhile t
        (recv
            ((event-data-rx . (? data)) (My_Data_Recv_Prog data))
            (_ nil)) 
            (event-handler) 
)))

(event-register-handler (spawn event-handler))

(event-enable 'event-data-rx)


;**** Program that monitors and debounces the trigger presses ****

(define SW_PRESSED 0)

(gpio-configure 'pin-ppm 'pin-mode-in-pd)

(spawn 25 (fn ()
(loopwhile t
   (if (= 1 (gpio-read 'pin-ppm))
            (setvar 'SW_PRESSED 1)
             ;else 
            (setvar 'SW_PRESSED 0)
   ) End of If trigger pressed statment
   (sleep 0.04)
)))

;**** End of Trigger Program  ****   

 
;**** Program that interprets the trigger clicks into single and double clicks and speed comands ****

(define SW_STATE 0)
(define SPEED 99) ;99 is off speed
(define Timer_Start 0)
(define Timer_Duration 0)
(define New_Start_Speed Start_Speed)
(define Custom_Control 0); variable to control Custom control on 5 clicks
(define Clicks 0)
(define Thirds-Total 0)
(define Warning-Counter 0); Count how many times the 3rds warnings have been triggered.

; Trigger_On_Time is 0.3 for Double Click Timer Settings
; Trigger_Off_Time is 0.5 for Double Click Timer Settings

(define Actual-Batt 0)
(define Temp-Batt 0)


 (defun SW_STATE_0 ()
  
    ;xxxx State "0" Off
    (loopwhile (= SW_STATE 0)
     (progn
   ;Claculate corrected batt %, only needed when scooter is off in state 0
   (setvar 'Temp-Batt (get-batt))
   (setvar 'Actual-Batt  (+ (* 4.3867 Temp-Batt Temp-Batt Temp-Batt Temp-Batt) (* -6.7072 Temp-Batt Temp-Batt Temp-Batt)(* 2.4021 Temp-Batt Temp-Batt)(* 1.3619 Temp-Batt )))  
   (sleep 0.02)   
        
        
     ;Pressed
     (if (= SW_PRESSED 1)
     (progn
      (setvar 'Batt_Disp_Timer_Start 0); Stop Battery Display in case its running
      (setvar 'Disp_Timer_Start 2); Stop Display in case its running
      (setvar 'Timer_Start (systime))
      (setvar 'Timer_Duration 0.3)
      (setvar 'Clicks 1)
      (setvar 'SW_STATE 1) 
      (spawn  40 SW_STATE_1) 
      (break)
      )))))  
       

(move-to-flash SW_STATE_0)



    ;xxxx STATE 1 Counting Clicks  
  
  (defun SW_STATE_1 ()
  
    (loopwhile (= SW_STATE 1)
    (progn
    (sleep 0.02)
    
      ;Released
     (if (= SW_PRESSED 0)
     (progn
     (setvar 'Disp_Timer_Start 2); Stop Display in case its running
     (setvar 'Timer_Start (systime))
     (setvar 'Timer_Duration 0.5)
     (setvar 'SW_STATE 3) 
     (spawn 35 SW_STATE_3)
     (break)
      ))
     
     ;Timer Expiry     
     (if (> (secs-since Timer_Start) Timer_Duration)    
     (progn
          
     ;Single Click Commands
     (if (and (= Clicks 1) (!= SPEED 99))
                (progn
                (setvar 'Click_Beep 1)
                (if (> SPEED 2)
                    (setvar 'SPEED (- SPEED 1)) ; decrease one speed
                    ;else
                    (if (= SPEED 0)
                        (setvar 'SPEED 1); set to untangle 
            
            ))))           
    
      ;Double Click Comands
     (if (= Clicks 2)
            (if (= SPEED 99)
            (setvar 'SPEED New_Start_Speed)
            ;else
            (progn
            (setvar 'Click_Beep 2)    
            (if (< Speed Max_Speed_No)
                (if (> SPEED 1)
                    (setvar 'SPEED (+ SPEED 1)); increase one speed
                ;else
                    (setvar 'SPEED 0); set to reverse "
                )
              )    
         )
     ))
     
     ;Triple Click Comands
     (if (= Clicks 3)
     (progn
         (if (!= SPEED 99)(setvar 'Click_Beep 3))
          (setvar 'SPEED Jump_Speed); Jump Speed
       ))
     
     ;Quadruple Click Comands
     (if (and (= Clicks 4) (= 1 Enable_Reverse))
             (progn
             (if (!= SPEED 99)(setvar 'Click_Beep 4))
             (setvar 'SPEED 1); set to untangle
      ))
      
     ;Quintuple Click Comands
     (if (= Clicks 5)
        (progn
        (setvar 'Click_Beep 5)
            (if (and (!= SPEED 99) (> Enable_Custom_Control 0) (< Custom_Control 1))
                        (setvar 'Custom_Control (+ 0.5 Custom_Control))
            )
      
            (if (= Custom_Control 0.5); If custom control is enabled, show it on screen    
                (progn
                    (setvar 'Disp-Num 16)
                    (setvar 'Last-Disp-Num 99); this display may be needed multiple times, so clear the last disp too
            ))
   
            (if (= Custom_Control 1); If custom control is enabled, show it on screen    
                (progn
                    (setvar 'Disp-Num 17)
                    (if (< SPEED 2) ; re command actuall speed as reverification sets it to 0.8x
                        (set-rpm (- 0 (* (/ (ix Max_ERPM Scooter_Type) 100)(ix Speed_Set SPEED))))
                        ;else
                        (set-rpm (* (/ (ix Max_ERPM Scooter_Type) 100)(ix Speed_Set SPEED)))
                        )
               )
            )
     ))
     
                      
                              
     ;End of Click Actions
     (setvar 'Clicks 0)
     (setvar 'Timer_Duration 999999)
     (setvar 'SW_STATE 2) 
     (spawn 30 SW_STATE_2)
     (break)
     ))
     ))             
)

(move-to-flash SW_STATE_1)

;xxxx State 2 "Pressed"
   (defun SW_STATE_2 ()
   (loopwhile (= SW_STATE 2)
   (progn
     (timeout-reset); keeps motor running
     (sleep 0.02)
     
     ;xxx repeat display section whilst scooter is running xxx
    
    
      (if (and (> (secs-since Timer_Start) 6) (= Custom_Control 0)) ; 6 = display duration +1
          (setvar 'Disp-Num Last-Batt-Disp-Num)
            
      )
      
    (if (and (> (secs-since Timer_Start) 12) (= Custom_Control 0)) ; 12= (2xdisplay duration + 2)
        (progn
            (setvar 'Disp-Num (+ SPEED 4)) 
            (setvar 'Timer_Start (systime))
      ))
 
    ;xxx end repeat display section
     
     (if (and (= Custom_Control 0.5) (> (secs-since Timer_Start) 5)); time out custom control if second activation isnt recieved within display duration
        (setvar 'Custom_Control 0)
     )
     
     ;Extra Long Press Commands when off (10 seconds)

     (if (and (> (secs-since Timer_Start) 10)  (= SPEED 99))  
     (progn
          (setvar 'Thirds-Total Actual-Batt)
          (spawn Warbler 450 0.2 0)
          (setvar 'Warning-Counter 0)
          ))
          
 
     ;Released
     (if (= SW_PRESSED 0)
     (progn
     (setvar 'Timer_Start (systime))
     (setvar 'Timer_Duration 0.5)
     (setvar 'SW_STATE 3) 
     (spawn 35 SW_STATE_3)
     (break)
     ))))
     )

(move-to-flash SW_STATE_2)


;xxxx State 3 "Going Off"
   (defun SW_STATE_3 ()
   (loopwhile (= SW_STATE 3)
   (progn
    (sleep 0.02)
    (if (> Custom_Control 0); If custom control is enabled, dont shut down    
                (timeout-reset) 
            ) 
    
           
     ;Pressed
     (if (= SW_PRESSED 1)
     (progn
      (timeout-reset); keeps motor running, vesc automaticaly stops if it doesnt recieve this command every second
      (setvar 'Timer_Start (systime))
      (setvar 'Timer_Duration 0.3)
      
      (if (= Custom_Control 1) ; if custom control is on and switch pressed, turn it off
            (setvar 'Custom_Control 0)
      ;else
            (if (< SAFE_START_TIMER 1) ; check safe start isnt running, dont allow gear shifts if it is on
            (setvar 'Clicks (+ Clicks 1)))
      )
      
                   
      (setvar 'SW_STATE 1)
      (spawn 40 SW_STATE_1) 
      (break)
     
          
      ))
        
     ;Timer Expiry
     (if (> (secs-since Timer_Start) Timer_Duration)    
      (progn
  
            (if (!= Custom_Control 1); If custom control is enabled, dont shut down
                (progn
                    (setvar 'Timer_Duration 999999); set to infinite
                    (if (< SPEED Start_Speed); start at old speed if less than start speed
                        (if (> SPEED 1)
                            (setvar 'New_Start_Speed SPEED)
                        )
                        ;else   
                        (setvar 'New_Start_Speed Start_Speed)
                    )                
                (setvar 'SPEED 99) 
                (setvar 'Custom_Control 0) ; turn off custom control
                (setvar 'SW_STATE 0)
                (spawn 35 SW_STATE_0) 
                (break) ;SWST_OFF   
            ))
      
                   
         
            (if (= Custom_Control 1); Require custom control to be re-enabled after a fixed duration 
                (if (> (secs-since Timer_Start) (* Custom_Control_Timeout 60)); 
                    (progn
                    (setvar 'Custom_Control 0.5)
                    (setvar 'Timer_Start (systime))
                    (setvar 'Timer_Duration 5); sets timer duration to display duration to allow for re-enable
                    (setvar 'Disp-Num 16)
                    (setvar 'Click_Beep 5)
                    (if (< SPEED 2) ; slow scooter to 80% to help people realize custom is expiring
                        (set-rpm (- 0 (* (/ (ix Max_ERPM Scooter_Type) 125)(ix Speed_Set SPEED))))
                        ;else
                        (set-rpm (* (/ (ix Max_ERPM Scooter_Type) 125)(ix Speed_Set SPEED)))
                    )
                    )
                ))
         
         
         )) ;end Timer expiry
            
         ))) ;end state
     
        
(move-to-flash SW_STATE_3)


 ; **** Function that sets the motor speeds ****


(define LAST_SPEED 99)
(define SAFE_START_TIMER 0)
(define Max_ERPM (list 4100 7100)) ;1st no is Blacktip, second is CudaX
(define Max_Current (list 22.8 46)) ;1st no is Blacktip, second is CudaX
(define Min_Current (list 1.7 0.35)) ;1st no is Blacktip, second is CudaX

(move-to-flash Max_ERPM Max_Current Min_Current)

(spawn 65 (fn ()
  (progn
  (loopwhile t
  (progn
    (loopwhile (!= SPEED LAST_SPEED)
    (progn
    (sleep 0.25)
;xxxx turn off motor if speed is 99, scooter will also stop if the (timeout-reset) command isnt recieved every second from the Switch_State program   
    (if (= SPEED 99)
       (progn
         (set-current 0)
         (setvar 'Batt_Disp_Timer_Start (systime)); Start trigger for Battery Display
         (setvar 'Disp-Num 14);Turn on Off display. (off display is needed to ensure restart triggers a new display number)
         (setvar 'SAFE_START_TIMER 0); unlock speed changes and disable safe start timer
         (setvar 'LAST_SPEED SPEED)
         ))
   
    (if (!= SPEED 99)
      (progn 
 ;xxxx Soft Start section for all speeds, makes start less judery    
        (if (= LAST_SPEED 99)
            (progn
            (conf-set 'l-in-current-max (ix Min_Current Scooter_Type))
            (setvar 'SAFE_START_TIMER (systime))
            (setvar 'LAST_SPEED 0.5)
            (if (< SPEED 2) (set-duty (- 0 0.06)) (set-duty 0.06))
         ))
                                                              
                                                                                                          
;xxxx Set Actual Speeds section 
                 
                                          
         (if (and (> (secs-since SAFE_START_TIMER) 0.5) (or (= Use_Safe_Start 0) (!= LAST_SPEED 0.5) (and (> (abs (get-rpm)) 350) (> (abs (get-duty)) 0.05) (< (abs (get-current)) 5))))
         
         (progn
         (conf-set 'l-in-current-max (ix Max_Current Scooter_Type))
         
                                                                             
         ;xxx reverse gear section
         (if (< SPEED 2)
             (set-rpm (- 0 (* (/ (ix Max_ERPM Scooter_Type) 100)(ix Speed_Set SPEED))))
         ;else
         ;xxx Normal Gears Section
         (set-rpm (* (/ (ix Max_ERPM Scooter_Type) 100)(ix Speed_Set SPEED)))
         )
         
         (setvar 'Disp-Num (+ SPEED 4))        
         ;Maybe causing issues with timimg? (setvar 'Timer_Start (systime)) ; set state timer so that repeat display timing works in state 2
         (setvar 'SAFE_START_TIMER 0); unlock speed changes and disable safe start timer
         (setvar 'LAST_SPEED SPEED)
          ))

        ;exit and stop motor if safestart hasnt cleared in 0.5 seconds and rpm is less than 500.
        (if (and (> (secs-since SAFE_START_TIMER) 0.5) (> (abs (get-current)) 8) (< (abs (get-rpm)) 350) (= Use_Safe_Start 1) (= LAST_SPEED 0.5 ))
         (progn
         (setvar 'SPEED 99)
         (setvar 'SW_STATE 1) 
         (spawn 40 SW_STATE_1)
         (foc-beep 250 0.15 5)
         ))

   
          ))

          )))))))
  
; **** Program that controls the display ****

(def Displays [
0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x81 0 0x81 ; Display Battery 1 Bar Rotation 0
0 0x81 0 0x81 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 ; Display Battery 1 Bar Rotation 1
0 0x60 0 0x60 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 ; Display Battery 1 Bar Rotation 2
0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x60 0 0x60 ; Display Battery 1 Bar Rotation 3

0 0x00 0 0x00 0 0x00 0 0x00 0 0x06 0 0x06 0 0x87 0 0x87 ; Display Battery 2 Bars Rotation 0
0 0x81 0 0x81 0 0x87 0 0x87 0 0x00 0 0x00 0 0x00 0 0x00 ; Display Battery 2 Bars Rotation 1
0 0x78 0 0x78 0 0x18 0 0x18 0 0x00 0 0x00 0 0x00 0 0x00 ; Display Battery 2 Bars Rotation 2
0 0x00 0 0x00 0 0x00 0 0x00 0 0x78 0 0x78 0 0x60 0 0x60 ; Display Battery 2 Bars Rotation 3

0 0x00 0 0x00 0 0x18 0 0x18 0 0x1E 0 0x1E 0 0x9F 0 0x9F ; Display Battery 3 Bars Rotation 0
0 0x81 0 0x81 0 0x87 0 0x87 0 0x9F 0 0x9F 0 0x00 0 0x00 ; Display Battery 3 Bars Rotation 1
0 0x7E 0 0x7E 0 0x1E 0 0x1E 0 0x06 0 0x06 0 0x00 0 0x00 ; Display Battery 3 Bars Rotation 2
0 0x00 0 0x00 0 0x7E 0 0x7E 0 0x78 0 0x78 0 0x60 0 0x60 ; Display Battery 3 Bars Rotation 3

0 0x60 0 0x60 0 0x78 0 0x78 0 0x7E 0 0x7E 0 0xFF 0 0xFF ; Display Battery 4 Bars Rotation 0
0 0x81 0 0x81 0 0x87 0 0x87 0 0x9F 0 0x9F 0 0xFF 0 0xFF ; Display Battery 4 Bars Rotation 1
0 0xFF 0 0xFF 0 0x9F 0 0x9F 0 0x87 0 0x87 0 0x81 0 0x81 ; Display Battery 4 Bars Rotation 2
0 0xFF 0 0xFF 0 0x7E 0 0x7E 0 0x78 0 0x78 0 0x60 0 0x60 ; Display Battery 4 Bars Rotation 3

0 0x1F 0 0x3F 0 0x33 0 0x1F 0 0x0F 0 0x1B 0 0x33 0 0x33 ; Display Reverse Rotation 0
0 0x00 0 0xFF 0 0xFF 0 0x6C 0 0x6E 0 0xFB 0 0xB1 0 0x00 ; Display Reverse Rotation 1
0 0x33 0 0x33 0 0x36 0 0x3C 0 0x3E 0 0x33 0 0x3F 0 0x3E ; Display Reverse Rotation 2
0 0x00 0 0x63 0 0xF7 0 0x9D 0 0x8D 0 0xFF 0 0xFF 0 0x00 ; Display Reverse Rotation 3

0 0x33 0 0x33 0 0x33 0 0x33 0 0x33 0 0x33 0 0x3F 0 0x1E ; Display Untangle Rotation 0
0 0x00 0 0x7F 0 0xFF 0 0x81 0 0x81 0 0xFF 0 0x7F 0 0x00 ; Display Untangle Rotation 1
0 0x1E 0 0x3F 0 0x33 0 0x33 0 0x33 0 0x33 0 0x33 0 0x33 ; Display Untangle Rotation 2
0 0x00 0 0xBF 0 0xFF 0 0x60 0 0x60 0 0xFF 0 0xBF 0 0x00 ; Display Untangle Rotation 3

0 0x0C 0 0x0E 0 0x0E 0 0x0C 0 0x0C 0 0x0C 0 0x0C 0 0x1E ; Display One Rotation 0
0 0x00 0 0x00 0 0xB0 0 0xFF 0 0xFF 0 0x80 0 0x00 0 0x00 ; Display One Rotation 1
0 0x1E 0 0x0C 0 0x0C 0 0x0C 0 0x0C 0 0x1C 0 0x1C 0 0x0C ; Display One Rotation 2
0 0x00 0 0x00 0 0x40 0 0xFF 0 0xFF 0 0x43 0 0x00 0 0x00 ; Display One Rotation 3

0 0x1E 0 0x3F 0 0x31 0 0x18 0 0x06 0 0x03 0 0x3F 0 0x1E ; Display Two Rotation 0
0 0x00 0 0x33 0 0xE7 0 0xE5 0 0xE9 0 0xF9 0 0x31 0 0x00 ; Display Two Rotation 1
0 0x1E 0 0x3F 0 0x30 0 0x18 0 0x06 0 0x23 0 0x3F 0 0x1E ; Display Two Rotation 2
0 0x00 0 0x23 0 0xE7 0 0xE5 0 0xE9 0 0xF9 0 0x33 0 0x00 ; Display Two Rotation 3

0 0x1E 0 0x33 0 0x30 0 0x1C 0 0x3C 0 0x30 0 0x33 0 0x1E ; Display Three Rotation 0
0 0x00 0 0x21 0 0xE1 0 0xCC 0 0xCC 0 0xFF 0 0x37 0 0x00 ; Display Three Rotation 1
0 0x1E 0 0x33 0 0x03 0 0x0F 0 0x0E 0 0x03 0 0x33 0 0x1E ; Display Three Rotation 2
0 0x00 0 0x3B 0 0xFF 0 0xCC 0 0xCC 0 0xE1 0 0x21 0 0x00 ; Display Three Rotation 3

0 0x18 0 0x1C 0 0x1A 0 0x19 0 0x3F 0 0x3F 0 0x18 0 0x18 ; Display Four Rotation 0
0 0x00 0 0x0E 0 0x16 0 0x26 0 0xFF 0 0xFF 0 0x06 0 0x00 ; Display Four Rotation 1
0 0x06 0 0x06 0 0x3F 0 0x3F 0 0x26 0 0x16 0 0x0E 0 0x06 ; Display Four Rotation 2
0 0x00 0 0x18 0 0xFF 0 0xFF 0 0x19 0 0x1A 0 0x1C 0 0x00 ; Display Four Rotation 3

0 0x1E 0 0x03 0 0x03 0 0x1F 0 0x30 0 0x30 0 0x33 0 0x1E ; Display Five Rotation 0
0 0x00 0 0x39 0 0xF9 0 0xC8 0 0xC8 0 0xCF 0 0x07 0 0x00 ; Display Five Rotation 1
0 0x1E 0 0x33 0 0x03 0 0x03 0 0x3E 0 0x30 0 0x30 0 0x1E ; Display Five Rotation 2
0 0x00 0 0x38 0 0xFC 0 0xC4 0 0xC4 0 0xE7 0 0x27 0 0x00 ; Display Five Rotation 3

0 0x1E 0 0x23 0 0x03 0 0x1F 0 0x33 0 0x33 0 0x33 0 0x1E ; Display Six Rotation 0
0 0x00 0 0x3F 0 0xFF 0 0xC8 0 0xC8 0 0xCF 0 0x27 0 0x00 ; Display Six Rotation 1
0 0x1E 0 0x33 0 0x33 0 0x33 0 0x3E 0 0x30 0 0x31 0 0x1E ; Display Six Rotation 2
0 0x00 0 0x39 0 0xFC 0 0xC4 0 0xC4 0 0xFF 0 0x3F 0 0x00 ; Display Six Rotation 3

0 0x3F 0 0x33 0 0x30 0 0x18 0 0x0C 0 0x0C 0 0x0C 0 0x0C ; Display Seven Rotation 0
0 0x00 0 0x60 0 0x60 0 0xC7 0 0xCF 0 0x78 0 0x70 0 0x00 ; Display Seven Rotation 1
0 0x0C 0 0x0C 0 0x0C 0 0x0C 0 0x06 0 0x03 0 0x33 0 0x3F ; Display Seven Rotation 2
0 0x00 0 0x83 0 0x87 0 0xFC 0 0xF8 0 0x81 0 0x81 0 0x00 ; Display Seven Rotation 3

0 0x1E 0 0x21 0 0xD2 0 0xC0 0 0xD2 0 0xCC 0 0x21 0 0x1E ; Display Eight Rotation 0
0 0x1E 0 0x21 0 0xD4 0 0xC2 0 0xC2 0 0xD4 0 0x21 0 0x1E ; Display Eight Rotation 1
0 0x1E 0 0x21 0 0xCC 0 0xD2 0 0xC0 0 0xD2 0 0x21 0 0x1E ; Display Eight Rotation 2
0 0x1E 0 0x21 0 0xCA 0 0xD0 0 0xD0 0 0xCA 0 0x21 0 0x1E ; Display Eight Rotation 3

0 0x1E 0 0x21 0 0xC2 0 0xC4 0 0xC8 0 0xD0 0 0x21 0 0x1E ; Display Off Rotation 0
0 0x1E 0 0x21 0 0xC2 0 0xC4 0 0xC8 0 0xD0 0 0x21 0 0x1E ; Display Off Rotation 1
0 0x1E 0 0x21 0 0xC2 0 0xC4 0 0xC8 0 0xD0 0 0x21 0 0x1E ; Display Off Rotation 2
0 0x1E 0 0x21 0 0xD0 0 0xC8 0 0xC4 0 0xC2 0 0x21 0 0x1E ; Display Off Rotation 3

0 0x0C 0 0x2D 0 0xCC 0 0xCC 0 0xCC 0 0xC0 0 0x21 0 0x1E ; Display Startup Rotation 0
0 0x1E 0 0x21 0 0x80 0 0xFC 0 0xFC 0 0x80 0 0x21 0 0x1E ; Display Startup Rotation 1
0 0x1E 0 0x21 0 0xC0 0 0xCC 0 0xCC 0 0xCC 0 0x2D 0 0x0C ; Display Startup Rotation 2
0 0x1E 0 0x21 0 0x40 0 0xCF 0 0xCF 0 0x40 0 0x21 0 0x1E ; Display Startup Rotation 3

0 0x00 0 0x13 0 0xA8 0 0xA0 0 0x90 0 0x80 0 0x13 0 0x00 ; Display Custom ? Rotation 0
0 0x1E 0 0x21 0 0x21 0 0x00 0 0x10 0 0x25 0 0x18 0 0x00 ; Display Custom ? Rotation 1
0 0x00 0 0x32 0 0x40 0 0x42 0 0x41 0 0x45 0 0x32 0 0x00 ; Display Custom ? Rotation 2
0 0x00 0 0x06 0 0x29 0 0x02 0 0x00 0 0x21 0 0x21 0 0x1E ; Display Custom ? Rotation 3

0 0x1C 0 0x36 0 0x03 0 0x03 0 0x03 0 0x03 0 0x36 0 0x1C ; Display Custom Rotation 0
0 0x00 0 0x1E 0 0x3F 0 0xE1 0 0xC0 0 0xE1 0 0x21 0 0x00 ; Display Custom Rotation 1
0 0x0E 0 0x1B 0 0x30 0 0x30 0 0x30 0 0x30 0 0x1B 0 0x0E ; Display Custom Rotation 2
0 0x00 0 0x21 0 0xE1 0 0xC0 0 0xE1 0 0x3F 0 0x1E 0 0x00 ; Display Custom Rotation 3

0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x81 0 0x81 ; Display 3rds 1 Bar Rotation 0
0 0x81 0 0x81 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 ; Display 3rds 1 Bar Rotation 1
0 0x60 0 0x60 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 ; Display 3rds 1 Bar Rotation 2
0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x00 0 0x60 0 0x60 ; Display 3rds 1 Bar Rotation 3

0 0x00 0 0x00 0 0x00 0 0x0C 0 0x0C 0 0x0C 0 0x8D 0 0x8D ; Display 3rds 2 Bars Rotation 0
0 0x81 0 0x81 0 0x00 0 0x8F 0 0x8F 0 0x00 0 0x00 0 0x00 ; Display 3rds 2 Bars Rotation 1
0 0x6C 0 0x6C 0 0x0C 0 0x0C 0 0x0C 0 0x00 0 0x00 0 0x00 ; Display 3rds 2 Bars Rotation 2
0 0x00 0 0x00 0 0x00 0 0x7C 0 0x7C 0 0x00 0 0x60 0 0x60 ; Display 3rds 2 Bars Rotation 3

0 0x60 0 0x60 0 0x60 0 0x6C 0 0x6C 0 0x6C 0 0xED 0 0xED ; Display 3rds 3 Bars Rotation 0
0 0x81 0 0x81 0 0x00 0 0x8F 0 0x8F 0 0x00 0 0xFF 0 0xFF ; Display 3rds 3 Bars Rotation 1
0 0xED 0 0xED 0 0x8D 0 0x8D 0 0x8D 0 0x81 0 0x81 0 0x81 ; Display 3rds 3 Bars Rotation 2
0 0xFF 0 0xFF 0 0x00 0 0x7C 0 0x7C 0 0x00 0 0x60 0 0x60 ; Display 3rds 3 Bars Rotation 3

0 0x23 0 0x52 0 0x52 0 0x52 0 0x52 0 0x52 0 0x52 0 0xA7 ; Display 10 Percent Rotation 0
0 0x80 0 0xC0 0 0xFF 0 0x80 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 10 Percent Rotation 1
0 0x79 0 0x92 0 0x92 0 0x92 0 0x92 0 0x92 0 0x92 0 0x31 ; Display 10 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x40 0 0xFF 0 0xC0 0 0x40 ; Display 10 Percent Rotation 3

0 0xA3 0 0x54 0 0x54 0 0x54 0 0x53 0 0xD0 0 0xD0 0 0x27 ; Display 20 Percent Rotation 0
0 0x43 0 0xC4 0 0xC4 0 0xB8 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 20 Percent Rotation 1
0 0x39 0 0xC2 0 0xC2 0 0xB2 0 0x8A 0 0x8A 0 0x8A 0 0x71 ; Display 20 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x47 0 0xC8 0 0xC8 0 0xB0 ; Display 20 Percent Rotation 3

0 0xA3 0 0x54 0 0x54 0 0x53 0 0x54 0 0x54 0 0x54 0 0xA3 ; Display 30 Percent Rotation 0
0 0xC0 0 0xC8 0 0xC8 0 0x37 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 30 Percent Rotation 1
0 0x71 0 0x8A 0 0x8A 0 0x8A 0 0xB2 0 0x8A 0 0x8A 0 0x71 ; Display 30 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x3B 0 0xC4 0 0xC4 0 0xC0 ; Display 30 Percent Rotation 3

0 0x22 0 0x53 0 0xD2 0 0xD2 0 0xD7 0 0x52 0 0x52 0 0x22 ; Display 40 Percent Rotation 0
0 0x1C 0 0x24 0 0xFF 0 0x04 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 40 Percent Rotation 1
0 0x11 0 0x92 0 0x92 0 0xFA 0 0xD2 0 0xD2 0 0xB2 0 0x11 ; Display 40 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x08 0 0xFF 0 0x09 0 0x0E ; Display 40 Percent Rotation 3

0 0xA7 0 0xD0 0 0xD0 0 0x53 0 0x54 0 0x54 0 0x54 0 0xA3 ; Display 50 Percent Rotation 0
0 0xF0 0 0xC8 0 0xC8 0 0x47 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 50 Percent Rotation 1
0 0x71 0 0x8A 0 0x8A 0 0x8A 0 0xB2 0 0xC2 0 0xC2 0 0x79 ; Display 50 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0xB8 0 0xC4 0 0xC4 0 0xC3 ; Display 50 Percent Rotation 3

0 0x27 0 0xD0 0 0xD0 0 0xD3 0 0xD4 0 0xD4 0 0xD4 0 0x23 ; Display 60 Percent Rotation 0
0 0x3F 0 0xC8 0 0xC8 0 0x47 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 60 Percent Rotation 1
0 0x31 0 0xCA 0 0xCA 0 0xCA 0 0xF2 0 0xC2 0 0xC2 0 0x39 ; Display 60 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0xB8 0 0xC4 0 0xC4 0 0x3F ; Display 60 Percent Rotation 3

0 0xA7 0 0x54 0 0x54 0 0x53 0 0x52 0 0x51 0 0x51 0 0xA0 ; Display 70 Percent Rotation 0
0 0xC0 0 0x4B 0 0x4C 0 0x70 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 70 Percent Rotation 1
0 0x41 0 0xA2 0 0xA2 0 0x92 0 0xB2 0 0x8A 0 0x8A 0 0x79 ; Display 70 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x83 0 0x8C 0 0xB4 0 0xC0 ; Display 70 Percent Rotation 3

0 0x23 0 0xD4 0 0xD4 0 0xD4 0 0x53 0 0xD4 0 0xD4 0 0x23 ; Display 80 Percent Rotation 0
0 0x3B 0 0xC4 0 0xC4 0 0x3B 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 80 Percent Rotation 1
0 0x31 0 0xCA 0 0xCA 0 0xB2 0 0xCA 0 0xCA 0 0xCA 0 0x31 ; Display 80 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x37 0 0xC8 0 0xC8 0 0x37 ; Display 80 Percent Rotation 3

0 0x23 0 0xD4 0 0xD4 0 0x57 0 0x54 0 0x54 0 0x54 0 0xA3 ; Display 90 Percent Rotation 0
0 0xB0 0 0xC8 0 0xC8 0 0x3F 0 0x00 0 0x3F 0 0xC0 0 0x3F ; Display 90 Percent Rotation 1
0 0x71 0 0x8A 0 0x8A 0 0x8A 0 0xBA 0 0xCA 0 0xCA 0 0x31 ; Display 90 Percent Rotation 2
0 0x3F 0 0xC0 0 0x3F 0 0x00 0 0x3F 0 0xC4 0 0xC4 0 0x43 ; Display 90 Percent Rotation 3

0 0xE3 0 0x90 0 0x90 0 0x93 0 0x90 0 0x90 0 0x90 0 0xE0 ; Display 100 Percent Rotation 0
0 0xFF 0 0x48 0 0x48 0 0x00 0 0x00 0 0x3F 0 0xC0 0 0xC0 ; Display 100 Percent Rotation 1
0 0xC1 0 0x42 0 0x42 0 0x42 0 0x72 0 0x42 0 0x42 0 0xF1 ; Display 100 Percent Rotation 2
0 0xC0 0 0xC0 0 0x3F 0 0x00 0 0x00 0 0x84 0 0x84 0 0xFF ; Display 100 Percent Rotation 3


])

(move-to-flash Displays)


;List with all the screen Brightness commands
(define Brightness_Bytes (list 
0xE0; 0 Min
0xE3; 1 
0xE6; 2
0xE9; 3
0xEC; 4
0xEF; 5 Max
))
        
(move-to-flash Brightness_Bytes)
 
 (if (or (= 0 Bluetooth) (= 3 Bluetooth)) ; turn on i2c for the screen based on wiring. 0 = Blacktip with Bluetooth, 3 = CudaX with Bluetooth
     (i2c-start 'rate-400k 'pin-swdio 'pin-swclk); Works HW 60 with screen on SWD Connector. Screen SDA pin to Vesc SWDIO (2), Screen SCL pin to Vesc SWCLK (4)
     (if (or (= 1 Bluetooth) ( = 4 Bluetooth)) ;1 = Blacktip without Bluetooth, 4 = CudaX without Bluetooth
         (i2c-start 'rate-400k 'pin-rx 'pin-tx); Works HW 60 with screen on Comm Connector. Screen SDA pin to Vesc RX/SDA (5), Screen SCL pin to Vesc  TX/SCL (6)
         (if ( = 2 Bluetooth)
             (i2c-start 'rate-400k 'pin-tx 'pin-rx); tested on HW 410 Tested: SN 189, SN 1691
              (nil))))  
   
  (define mpu-addr 0x70) ; I2C Address for the screen     
 
  (i2c-tx-rx 0x70 (list 0x21)) ; start the oscillator 
  (i2c-tx-rx 0x70 (list (ix Brightness_Bytes Disp_Brightness)))  ;set brightness    
  
  (if (= Scooter_Type 1) ; For cuda X setup second screen
         (progn
         (i2c-tx-rx 0x71 (list 0x21)) ; start the oscillator
         (i2c-tx-rx 0x71 (list (ix Brightness_Bytes Disp_Brightness)))  ;set brightness    
   ))
               
               
    
  (define Start 0) ;variable used to define start position in the array of diferent display screens
  (define Disp-Num 1) ;variable used to define the display screen you are accesing 0-X
  (define Last-Disp-Num 1); variable used to track last display screen show
  (define pixbuf (array-create 16))  ;create a temp array to store display bytes in
  (bufclear pixbuf) ;clear the buffer  
  (define Disp_Timer_Start 0); Timer for display duration
  ;(define Disp_Duration 5) ; eliminated to save memory
          
(spawn 45 (fn ()
  (loopwhile t
  (progn
  (sleep 0.25)
;xxxx Timer section to turn display off, gets reset by each new request to display
  (if (> Disp_Timer_Start 1); check to see if display is on. dont want to run i2c comands continously
  (if (> (secs-since Disp_Timer_Start) 5) ;check timer to see if its longer than display duration and display needs turning off, new display comands will keep adding time
  (progn
  
  (if (= Scooter_Type 0) ;For Blacktip Turn off the display
        (if (!= Last-Disp-Num 17); if last display was the custom control, dont disable display
            (i2c-tx-rx 0x70 (list 0x80))))
   ;else For Cuda X make sure it doesnt get stuck on diaplaying B1 or B2 error, so switch back to last battery.
  (if (and (= Scooter_Type 1) (> Last-Disp-Num 20) ) 
      (setvar 'Disp-Num Last-Batt-Disp-Num))
   
  (setvar 'Disp_Timer_Start 0) 
  )))
;xxxx End of timer section   

    (if (!= Disp-Num Last-Disp-Num)
    (progn
    (if (= Scooter_Type 1) ; For cuda X second screen
        (progn
        (if (= CudaX_Flip 1)
            (setvar 'mpu-addr 0x70)
            (setvar 'mpu-addr 0x71)
        )
        (if (or (= Disp-Num 0) (= Disp-Num 1) (= Disp-Num 2) (= Disp-Num 3) (> Disp-Num 17) )
            (if (= CudaX_Flip 1)
                (setvar 'mpu-addr 0x71)
                (setvar 'mpu-addr 0x70)
        )    )
    ))
    (setvar 'Disp_Timer_Start (systime))
    (if (= mpu-addr 0x70)
        (setvar 'Start (+(* 64 Disp-Num) (* 16 Rotation))) ;define the correct start position in the array for the display
        (setvar 'Start (+(* 64 Disp-Num) (* 16 Rotation2)))
        )
    (bufclear pixbuf)
    (bufcpy pixbuf 0 Displays Start 16) ;copy the required display from "Displays" Array to "pixbuf"
    (i2c-tx-rx mpu-addr pixbuf) ;send display characters
    (i2c-tx-rx mpu-addr (list 0x81)) ;Turn on display
    (setvar 'Last-Disp-Num Disp-Num)
    (setvar 'mpu-addr 0x70)
        ))
                                   
      ))))
 ; **** End of Display program ****                       
 
 
 ; **** Program that triggers the display to show battery status **** 

(define Batt_Disp_Timer_Start 0) ;Timer to see if Battery display has been triggered     
(define Last-Batt-Disp-Num 3); variable used to track last display screen show
(define Batt-Disp-State 0)

(spawn 45 (fn ()
(loopwhile t
    (progn
       (sleep 0.25)
       
        (if (or (= Batt_Disp_Timer_Start 0) (= Batt-Disp-State 0))
        (progn
        (setvar 'Batt-Disp-State 0)))
        
        
        (if (and (> Batt_Disp_Timer_Start 1) (> (secs-since Batt_Disp_Timer_Start) 6) (= Batt-Disp-State 0)); waits Display Duration + 1 second after scooter is turned off to stabalize battery readings
        (progn
        
        ;xxxx Section for normal 4 bar battery capacity display 
             
             (if (= Thirds-Total 0)      
                               
             (if (>  Actual-Batt 0.75) (progn (setvar 'Disp-Num 3) (spawn Beeper 4)) ; gets the vesc battery % and triggers the display screen
                ;else
                (if (> Actual-Batt 0.5) (progn (setvar 'Disp-Num 2) (spawn Beeper 3))
                    ;else
                    (if (> Actual-Batt 0.25) (progn (setvar 'Disp-Num 1) (spawn Beeper 2))
                        ;else
                        (progn (setvar 'Disp-Num 0) (spawn Beeper 1)) (nil ))))
           
             ;else Section for 1/3rds display
            
              (if (and (> Actual-Batt (* Thirds-Total 0.66)) (= Warning-Counter 0)) (progn (setvar 'Disp-Num 20))
                ;else
                (if (and (> Actual-Batt (* Thirds-Total 0.33)) (< Warning-Counter 3))
                 (progn 
                 (setvar 'Disp-Num 19)
                  (if (< Warning-Counter 2)
                   (progn
                    (spawn Warbler 350 0.5 0.5)
                     (setvar 'Warning-Counter (+ Warning-Counter 1)
                     ))))
                    ;else
                    (progn
                     (setvar 'Disp-Num 18)
                     (if (< Warning-Counter 4)
                        (progn
                        (spawn Warbler 350 0.5 0.5)
                        (setvar 'Warning-Counter (+ Warning-Counter 1))))) (nil ))))
                    
                 (setvar 'Batt-Disp-State 1) 
                 (setvar 'Last-Batt-Disp-Num Disp-Num)  
                    ))
       
         (if (and (> Batt_Disp_Timer_Start 1) (> (secs-since Batt_Disp_Timer_Start) 12) (= Batt-Disp-State 1) (> Thirds-Total 0)) 
        (progn            
              
              (if (>  Actual-Batt 0.95) (progn (setvar 'Disp-Num 30)) ; gets the vesc battery % and triggers the display screen NOTE % are adjusted to better represent battery state, ie fully charged power tool battery will not display at 100% on the vesc
                ;else
                (if (> Actual-Batt 0.90) (progn (setvar 'Disp-Num 29)) ;90%
                    ;else
                    (if (> Actual-Batt 0.80) (progn (setvar 'Disp-Num 28)) ;80%
                        ;else
                        (if (> Actual-Batt 0.70) (progn (setvar 'Disp-Num 27));70%
                            ;else
                            (if (> Actual-Batt 0.60) (progn (setvar 'Disp-Num 26));60%
                                ;else
                                (if (> Actual-Batt 0.50) (progn (setvar 'Disp-Num 25)) ;50%
                                    ;else
                                    (if (> Actual-Batt 0.40) (progn (setvar 'Disp-Num 24));40%
                                        ;else
                                       (if (> Actual-Batt 0.30) (progn (setvar 'Disp-Num 23)) ;30%
                                            ;else
                                            (if (> Actual-Batt 0.20) (progn (setvar 'Disp-Num 22)) ;20%
                                                ;else
                                                (progn (setvar 'Disp-Num 21)) (nil ))))))))))
               (setvar 'Batt-Disp-State 0)                                  
               (setvar 'Batt_Disp_Timer_Start 0)                                
              ))          
            
     ))))
             
    ;xxxx Beeps Program xxxx"
   
   (defun Beeper (Beeps)
   (loopwhile (and (= Enable_Battery_Beeps 1) (> Batt_Disp_Timer_Start 0) (> Beeps 0))
   (progn  
          (sleep 0.25)
          (foc-beep 350 0.5 Beeps_Vol)
         (setvar 'Beeps (- Beeps 1))
       )))
            
   (move-to-flash Beeper)   
    
    ;xxxx Warbler Program xxxx"
   
   (defun Warbler (Tone Time Delay)
            (progn
            (sleep Delay)
            (foc-beep Tone Time Beeps_Vol)
            (foc-beep (- Tone 200) Time Beeps_Vol)
            (foc-beep Tone Time Beeps_Vol)
            (foc-beep (- Tone 200) Time Beeps_Vol)
            ))
  
    (move-to-flash Warbler) 

                                                                                                                                  
       ;***** Program that beeps trigger clicks
       
       (define Click_Beep 0)
       (define Click_Beep_Timer 0) 
       
    (spawn 35 (fn ()
    (loopwhile t
    (progn  
    (sleep 0.25)
    
    (if (and (> (secs-since Click_Beep_Timer) 0.25) (!= Click_Beep_Timer 0))
    (progn
    (foc-play-stop)
    (setvar 'Click_Beep_Timer 0)
    ))
    
    (if (> Click_Beep 0) 
    (progn
    (if (and (= Click_Beep 5) (> Enable_Custom_Control 0)(!= SPEED 99)) (foc-play-tone 1 1500 Beeps_Vol))
    (if (= Enable_Trigger_Beeps 1)
    (progn
    (if (= Click_Beep 1)(foc-play-tone 1 2500 Beeps_Vol))
    (if (= Click_Beep 2)(foc-play-tone 1 3000 Beeps_Vol))
    (if (= Click_Beep 3)(foc-play-tone 1 3500 Beeps_Vol))
    (if (= Click_Beep 4)(foc-play-tone 1 4000 Beeps_Vol))
    ))
    
    (setvar 'Click_Beep_Timer (systime))
    (setvar 'Click_Beep 0)
    ))
    
    ))))
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
      ;******* End of trigger click beeps     
      
     
 
     (spawn 35 SW_STATE_0) ;***Start state machine runnning for first time
 
     (setvar 'Disp-Num 15); display startup screen, change bytes if you want a different one
     (setvar 'Batt_Disp_Timer_Start (systime)); turns battery display on for power on.
