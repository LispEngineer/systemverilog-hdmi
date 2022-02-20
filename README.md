# Pure RTL HDMI Output

This project aims to demonstrate 1080p HDMI output using nothing
but pure SystemVerilog, targeting an
[Analog Devices ADV7513 HDMI Transmitter](https://www.analog.com/en/products/adv7513.html).
The initial implementation board is a 
[Terasic Cyclone V GX Starter Kit](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=165&No=830&PartNo=2),
and is built with 
[Intel Quartus Prime Lite 21.1](https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html).

It was frustrating to me that most HDMI output demonstrations for
this chip used a soft CPU to handle the I2C configuration, as
I have numerous projects in mind that will not have a soft CPU.

## Testing

Testing was accomplished via simulation with 
[Questa Intel FPGA Edition](https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/questa-edition.html), which seems to be the latest
version of the ModelSim simulator. Further testing was done using the
[SignalTap Logic Analyzer](https://www.intel.com/content/www/us/en/docs/programmable/683819/21-3/design-debugging-with-the-logic-analyzer-69524.html).
Additional testing was done by routing signals externally
to GPIOs and using a 
[Digilent Analog Discovery 2](https://digilent.com/shop/analog-discovery-2-100ms-s-usb-oscilloscope-logic-analyzer-and-variable-power-supply/)
USB 2.0 logic analyzer and its associated
[Waveforms](https://digilent.com/shop/software/digilent-waveforms/) software.

In addition, "scaffolding" was used to see what was going on at the highest level, sort of like
inserting debugging print statements in programming languages. Various LEDs are used to show the status of signals and inputs.

### I2C Controller Testing

The I2C controller was tested and validated by connecting it
to an external OLED display powered by a SH1106 controller,
using 4.7 kOhm pull-up resistors connected to the GPIO pins.
(The SH1106 driver and test code is not part of this project.)
This was necessary as the `Cyclone V GX Starter Kit` does not
have an easy way to physically tap the internal I2C bus pins.

In addition to the simulator and SignalTap, a
[Rigol DS1074Z-S Plus](https://www.rigolna.com/products/digital-oscilloscopes/1000z/)
mixed signal oscilloscope (with logic analyzer probes) 
was used as well, but the Analog Discovery proved much
easier to use for decoding long sequences of I2C commands.

## IP Blocks

Despite the goal, it is necessary to use a few Altera-specific
IP blocks, for expected purposes:

* [ALTIOBUF](https://www.intel.com/content/www/us/en/docs/programmable/683471/19-1/ip-core-user-guide.html)
  was used to provide tri-state pin connections for the I2C clock & data
  signals, configured with the "open drain" option. I was unable to get
  the typical `assign GPIO = enable ? output : 1'bz; assign input = GPIO;`
  tri-state pin to synthesize in a way that worked with the external I2C
  devices, probably because it did not specify the 
  [OPEN_DRAIN_OUTPUT](https://www.intel.com/content/www/us/en/docs/programmable/683471/19-1/signals-and-parameters-as-bidirectional.html) behavior.

* [Altera PLL](https://www.intel.com/content/www/us/en/docs/programmable/683359/17-0/altera-phase-locked-loop-ip-core-user-guide.html)
  was used to access the Cyclone V GX's internal fractional PLL,
  to generate a 148.5 MHz clock from the externally provided 50 MHz
  clock. This is used for the HDMI 1080p pixel clock.

## Code Generator

The [Terasic C5G System Builder](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=165&No=830&PartNo=4#contents)
was used to build the Quartus project top-level and make all the correct pin
assignments. Note that it is important *not* to include features not in use
or not planned for use, because not terminating those pins in the SystemVerilog
correctly will result in all sorts of placement problems. I kept the
UART and SRAM in case those would become handy for later phases of this
project.

Originally I did not plan to use the GPIOs (silly choice) and added them later
by copying the settings to the `C5G_2HDMI.qsf` file from a blank project,
and commenting out the `HEX` pins that conflict with the `GPIO` pins
(see the C5G board documentation for overlaps between GPIO, HEX LEDs, and the
Arduino header).

# Operation

Connect your HDMI monitor and download the program to the board.
Depending on your switch settings, if all goes correctly, a 1080p
signal should be received by the monitor and displayed.

Inputs:

* `KEY3` is a reset key. `LEDG7` shows the state of the key input
  (it is positive when not pressed), and `LEDG6` shows the state of
  its use as a positive reset. So, usually `LEDG7` is lit unless you
  are pushing `KEY3`.
* `SW3` to `SW0` are the inputs to the pattern generator selector.
  The patterns currently available are:
    * 0: A solid 50% gray screen.
    * 1: A single pixel white border with black interior.
    * 2: Vertical 1-pixel lines alternating white/black.
    * 3: Horizontal 1-pixel lines, alternating white/black.
    * 4: A grayscale ramp from black to white going from left to right.
    * 5: A repeated set of red & green 256x256 ramps, with some blue
      variations "for fun."
    * 6: A checkerboard of alternating white/black.
    * 7: A full-screen color that shifts slowly over time in a silly way.
    * 8: A 45 degree diagonal line from top left to bottom right (not the corner)
    * Anything else is just a yellowish screen.

Visible outputs:
* `LEDR9` shows the `PLL Locked` signal for the 148.5 MHz generator.
* `LEDR8` through `LEDR5` show information about the ADV7513 I2C setup state machine.
    * `LEDR8` shows if the ADV7513 I2C setup state machine is active.
    * `LEDR7` shows if the ADV7513 I2C setup state machine is done.
    * `LEDR6` shows if the ADV7513 I2C setup state machine is waiting on the
    I2C controller to finish sending a command (`busywait` state).
    * `LEDR5` shows if the ADV7513 I2C setup state machine has seen the
    I2C controller become busy, so it can wait for it to become non-busy
    again.
* `LEDG0` through `LEDG4` show information about the I2C controller state machine.
  * `LEDG0` shows if the I2C controller is busy.
  * `LEDG1` and `LEDG2` are not connected due to incomplete implementation, but
    would show the I2C controller's results: abort or success respectively.
    (Abort will be asserted if we do not get an ACK during a write, and the
    controller stopped sending possibly early.)
  * `LEDG3` blinks when the controller starts processing a request or stops.
    (In practice this is too short to see, as it is a 1.2MHz blink.)
  * `LEDG4` is asserted when the I2C controller receives an ACK during a write
    operation.
* `HEX0` and `HEX1` just show a pattern.

GPIO outputs are used to provide external access to copies of the
internal I2C signals for use with an external logic analyzer.
Unfortunately, there is no easy way to access the actual I2C bus
between the FPGA and the ADV7513 without using an HSMC expansion
board.
* `GPIO5` to `GPIO3`: I2C SCL signal: enable, output, input respectively.
  (I do not think the input shows anything useful on the logic analyzer.)
* `GPIO8` to `GPIO6`: As above, for the I2C SDA signal.
* `GPIO9`: The I2C controller's ACK seen signal (as in `LEDG4` above).
* `GPIO10`: The I2C controller's `success` signal (not yet implemented).

## Misc Notes

The Terasic Cyclone V GX Starter Kit does not support HDMI sound output,
at least not without modifying the board. The ADV7513 sound inputs are
not connected, but pads are provided.

There is something about using "official" HDMI vs. using DVI over HDMI cable that
I don't really follow. For pure video output, DVI capabilities suffice for my needs so
I did not look into it.

ADV7513 supports HDCP, but I don't.

The ADV7513 tops out around 1080p; it doesn't support HDMI 2.0 or 4K video.

I am only using 24-bit RGB; the ADV7513 supports a variety of other color encodings
including, apparently, HDR.

The ADV7513 provides an interrupt input which can signal events like
a monitor being dis/connected. This requires reading information from
I2C, which I have not yet implemented. So, this implementation may be
fragile. See, in particular, some of the notes in the `C5G_HDMI_VPG`
project and how it implements handling the interrupt (available on
the [C5G System CD](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=830&PartNo=4)).

# Block Diagram

Top level:

```
CLOCK -> PLL HDMI CLOCK -+-> HDMI TOP -> ADV7513
         PATTERN SELECT -/

CLOCK -> ADV7513 SETUP <-> I2C CONTROLLER <-> ALTIOBUF <-> I2C BUS
```

HDMI top level:

```
   HDMI CLOCK -+-> SYNC GENERATOR -+-> PATTERN GENERATOR -> ADV7513
TIMING COUNTS -/                   |
                   PATTERN SELECT -/
```

# Implementation Notes

## I2C Controller

The I2c Controller is
implemented only as a `single controller` configuration
and does not support `clock stretching`, or any other
optional feature. It operates at both Standard-mode
and Fast-mode speeds.

Limitations:
* Supports only write commands
* Does not do restarts
* Does not gracefully handle a reset (e.g., by sending
  a `STOP` condition before resetting)
* Does not use `SCL` inputs since `clock stretching`
  is not implemented, although it offers a bidirectional
  `SCL` interface.
* Does not (yet) abort a write transaction when an
  `ACK` is not received.
* Does not signal success or failure (abort) of the most
  recent (write) command.

Capabilities:
* Defaults to a 390.625 kHz I2C clock when fed with a
  50 MHz system clock.
* Tested at 100 kHz and 400 kHz I2C clock rates.
* Tested externally with 4.7 kOhm pull-up resistors and
  an SH1106 OLED display target.
* Tested with this board's internal I2C bus communicating
  to the AN7513 HDMI transmitter.

The implementation takes the system clock and operates off that,
to avoid having any clock domain crossing issues.

It operates by way of an internal 32 clock divider (by default,
this is parameterized). This creates a 4x I2C clock speed
input to the state machine. 

The 4x speed allows us to generate an I2C clock (`SCL`) every four
I2C controller cycles with a `LOW HIGH HIGH LOW` output on
the I2C clock signal line. This is necessary because two
signals, the `STOP` and `START` conditions, require the
`SDA` line to change while the `SCL` line is held high.
All other `SDA` signals must stay stable while `SCL` is high.
(It will also be helpful when we implement `clock stretching`.)

The controller does not implement any tri-state capabilities;
instead it sends an output enable signal for both `SCL` and `SDA`.
The input capablities on the `SCL` are not yet used.

The controller is not (yet?) nicely split between state machine and
combinatorial sections and can probably be highly optimized.

# TODOs

* Consider expanding the main `reset` to include both the key,
  and for anything that isn't the PLL, the PLL locked signal.
  This way reset will be asserted until the PLL locks as well,
  preventing possibly undesired behavior with the ADV7513.
* Make the project "multisync" in that it could output several
  different HDMI signals, changing while operating. 
  I'd like to see 1280x1024 output as
  well as 720p, and whatever other sizes I have native LCD
  panels for (like 1680x1050 and 1600x1200). 
  Using a reconfigurable PLL
  would be preferred.
* Display images in the pattern generator from block RAM.
  Start with 1 bit pixmaps (as that is an important use case
  for a follow-on project).
* FIXME: `DE` signal is `Data Enable` in the ADV7513 document,
  but I call it `Display Enable` in my comments.
* A ton of TODOs on the I2C Controller, such as supporting
  read commands and restarts.
* If I really wanted to get advanced, I could have the system
  read the native resolution from EDID and switch output to
  that resolution.

# References

* [Intel Cyclone V GX FPGA](https://www.intel.com/content/www/us/en/products/details/fpga/cyclone/v/docs.html?s=Newest): Here are the Intel documents on this FPGA.
  I recall Altera had better organized documentation back before Intel took it over.
  I would look at the Overview and the Datasheet to start, and glance through the Errata.
  The fun starts in the Cyclone V Device Handbook, all four volumes,
  which seem to be very hard to find on
  Intel's site.

* [I2C Specification](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)
  UM10204, Revision 7.0, 1 October 2021, is what I used to learn
  I2C and implement the I2C controller.

* [I2C Manual](https://www.i2c-bus.org/specification/) AN10216-01
  may be useful to some. There are lots of I2C writeups and YouTube videos
  of I2C you can find by Googling around a little.

* [Analog Devices ADV7513](https://www.analog.com/en/products/adv7513.html):
  Required reading are the 
  [data sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ADV7513.pdf),
  the [hardware guide]()
  and the [programming guide]().

* [Analog Devices AN-1270](https://www.analog.com/media/en/technical-documentation/application-notes/an-1270.pdf):
  Gives an example sync and pattern generator for the ADV7513, and most
  importantly, a working initialization sequence to send over I2C.

* [VESA Display Monitor Timing](https://vesa.org/vesa-standards/)
  (freely available, but without registration 
  [here](https://glenwing.github.io/docs/VESA-DMT-1.13.pdf)):
  Section 3, "DMT Video Timing Parameter Definitions" is absolute
  required reading, showing how the sync pulses are generated,
  and where the visible video signal goes. Page 89 shows the
  1920x1080p60 detailed timings. Using this, it is straight forward
  to generate the HDMI signals: Horziontal Sync, Vertical Sync and
  the data signals to put visible content in the correct place,
  not to mention the correct HDMI clock frequency.

* [Data Enable](https://www.analog.com/en/analog-dialogue/articles/hdmi-made-easy.html)
  is an HDMI signal that "indicates an active region of video."

* [SH1106 OLED Controller](https://www.velleman.eu/downloads/29/infosheets/sh1106_datasheet.pdf)
  was used to test and verify the I2C controller on a real, external device.
  (It is a well written datasheet, IMO.)
  [This device](https://www.amazon.com/gp/product/B01MRR4LVE/) is what was used;
  it seems to operate fine with 3.3V. It works with no initialization, just
  send the `Display ON` command over I2C (which shows random stuff initially),
  set the page and column address, and then start writing data. (I would write
  data in 8 byte chunks. Even at 400 kHz you could see the data being written
  sometimes.) One note is that the first two columns are not on the display; the
  display starts at the third column (column 3).


# Misc

* In Visual Studio Code on Windows, Control-Shift-V previews a Markdown file.

# Copyright & License

Copyright 2022 [Douglas P. Fields, Jr.](mailto:symbolics@lisp.engineer) All Rights Reserved.
