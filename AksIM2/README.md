# AksIM-2 custom encoder implementation.

AksIM-2 absolute encoder single turn with 18bit resolution

## Implementation
Current implementation uses COM port on VESC controller to handle SPI coms to AksIM-2 encoder. MOSI line is not currently used and is tied to GND. It is mostly based off the As504x implementation with specifics updated for the AksIM-2 encoder

Controller starts communication by setting the NSS(NCS) signal low (Idle is high). At the same time the encoder position is latched, a delay of ts is required to allow encoder to prepare data.
This delay must be > 5us, currently using double this (10us). The encoder data is then shifted to the MISO output on the rising edge of the clock signal, SCK. Min clock period is 250us -> max frequency of 4MHz. SCK is pulled low once MISO pad is read.

This timing is important, if not followed you will get junk.

## Message Format

    b31:10      Encoder position + zero padding bits - Left Aligned, MSB first
    b9          Error - If low the position data is not valid
    b8          Warning - If low the position data is valid, but some operating conditions are close to limits
    b7:b0       Inverted CRC, 0x97 polynomial

From message format for 18bit resolution the message stream recieved is the 18bit encoder position, MSB first. Then four unused bits as we only require 18 bits of the 22 bit data message allocation, the error bit, the warning bit and finally the CRC.

 ## Note
 Packge was developed on and tested using Trampa 100_250 board. Package has been written using vesc interface options to attempt to make it 
 hardware agnostic but this has not been tested and no guarantee it will work.

## Debug
Some basic debugging has been added to package and can be used via lisp REPL
debug called using "(ext-aksim2-dbg idx)" where idx is the index of the debug value you wish to see.

Idex    Debug
1       spi raw value
2       last calculated angle
3       last message time
4       spi error count
5       error rate
6       is connected


## Datasheet
https://www.rls.si/eng/fileuploader/download/download/?d=1&file=custom%2Fupload%2FMBD01_10EN_datasheet_bookmark.pdf

## TODO
If two way SPI communication was established we could trigger self calibration of the encoder...

