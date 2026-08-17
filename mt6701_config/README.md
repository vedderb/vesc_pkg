# VL ABI Encoder Config (MT6701)

This package can be used to configure the [VESC Labs ABI encoder](https://www.vesclabs.com/product/vl-abi-encoder/) over I2C. This is useful for setting the number of pole pairs when using it in hall sensor mode. Using the encoder in hall sensor mode is useful on dual motor controllers which only support hall sensors such as the VESC Duet and the VESC Duet XS.

Hall sensor signals have lower bandwidth than an ABI signals and work without the PWM pin, so hall sensor mode can be more robust when position resolution at low speed is not important. Compared to regular hall sensors an encoder in hall sensor mode will generally perform better as it will have nearly perfect alignment.

**NOTE**  
The maximum number of pole pairs supported is 16. If your motor has more than 16 pole pairs (32 poles) the encoder cannot be used in hall sensor mode.

To use this package you can use the following procedure:

1. Set the encoder to I2C mode using the switch on the PCB.
2. Connect the 7-pin connector on the encoder as follows:

```
| ABI Encoder | Duet, Classic | Maxim, Pronto |
-----------------------------------------------
| GND         | GND           | GND           |
| EncA        | RX            | Hall 1        |
| EncB        | TX            | Hall 2        |
| 5V          | 5V            | 5V            |
```

3. Select the number of pole pairs and press write in the package UI. It will print the result of the operation on the package UI. The configuration is stored to non-volatile memory on the encoder.

4. Put the switch back to the ABI position.

5. Connect the encoder to the hall sensor port using the 6-pin connector.