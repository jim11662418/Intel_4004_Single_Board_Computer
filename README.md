# Intel 4004 Single Board Computer
### Overview
I built this Intel 4004 Single Board Computer a few years back to celebrate the 40th anniversary of the Intel 4004 CPU using ICs that I purchased on eBay. This homebrew, wire-wrap single board computer features:
- Intel 4004 CPU
- Intel 4201 Clock Generator
- Intel 4002 Static RAM (2X for a total of 640 *bits* of data memory)
- Intel 4289 Standard Memory Interface
- Intel 4265 General Purpose I/O Device
- 2732 EPROM for program storage
- 4 LEDs controlled by an output port on one of the 4002s
- 16 position rotary switch for selection of program options
- RS232 console serial port
<p align="center"><img src="/images/4004%20SBC.JPG"/>
<p align="center">Home-brew Intel 4004 SBC</p><br>

### 4004 SBC CPU and Memory
The CPU and Memory section of the Single Board Computer consists of an Intel 4004 CPU, a 4201 Clock Generator, two 4002 RAM chips with output ports (for a total of 640 bits of RAM), a 4289 Standard Memory Interface which provides the interface to a 2732 4K EPROM for program memory and a 4265 General purpose I/O Device.
<p align="center"><img src="/images/4004%20SBC%20CPU.png"/>
<p align="center">4004 SBC CPU and Memory Schematic</p><br>

The empty 24 pin socket shown in the photo above optionally allows the use of a 4040 CPU in place of the 4004 CPU. The 4004 CPU must be removed from its socket if the 4040 CPU is installed and vice-versa.
<p align="center"><img src="/images/4040%20SBC%20CPU.png"/>
<p align="center">4040 SBC CPU and Memory Schematic</p><br>

### 4004 SBC I/O
The Input/Output section of the 4004 Single Board Computer consists of two 4 bit output ports and four 4 bit ports that can be programmed as either input or output. The two 4002 RAM chips provide the output ports. A 4265 provides the four programable 4 bit I/O ports.

The output port on the first 4002 (address 0x40) is used to control the four LEDs. One bit of the output port on the second 4002 (address 0x00) is used to provide a bit-banged RS232 serial transmit output.

The 4004's TEST input is used for the RS232 serial receive input.

One of the 4265's ports (port W  at address 0x80) is used to read the four bit, sixteen position rotary switch. 

The 4049 CMOS Inverters are used as buffers and level converters.
<p align="center"><img src="/images/4004%20SBC%20IO.png"/>
<p align="center">4004 SBC I/O Schematic</p><br>

### 4004 SBC Power Supply
The 4004 single board computer's power supply shown below uses a Radio Shack transformer and a dual linear adjustable power supply module purchased on eBay to produce to +5VDC and -10VDC that the SBC requires. 

<p align="center"><img src="/images/4004%20SBC%20PS.png"/>
<p align="center">4004 SBC Power Supply Schematic</p>
<p align="center"><img src="/images/PS2.JPG"/>
<p align="center">4004 SBC Power Supply Transformer</p><br>
<p align="center"><img src="/images/PS1.JPG"/>
<p align="center">4004 SBC Power Supply Module</p><br>

### 4004 SBC Firmware
The [4004 SBC firmware](firmware.asm) was assembled with the [Macro Assembler AS](http://john.ccac.rwth-aachen.de:8000/as/). 

<p align="center"><img src="/images/4004 SBC Firmware.jpg"/>
<p align="center">4004 SBC Firmware</p><br>
