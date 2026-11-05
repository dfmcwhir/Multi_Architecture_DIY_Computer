# <h2> Advanced I/O Card</h2>
<p>New card that hasn't been built or tested yet. It has 3 functions:
<ol>1. SPI Interface</ol>
<ol>2. CH376 USB module</ol>
<ol>3. IDE interface</ol></p>

<p>The SPI and IDE interface essentially the same circuit and firmware that Daryl Rictor created. Documented here: https://sbc.rictor.org/65spi2.html and here: https://sbc.rictor.org/ide.html. The only real differences are a small change in the ide circuit and firmware to use an ATMEGA32 instead of an ATMEGA324 and using a DS1302 RTC module instead of a discrete DS1302 chip and supporting components.</p>

<p>The SPI controller will require 4 addresses (Exact addresses TBD, but will likely use some of the addresses freed from replacing the old CH376 USB card) and the USB controller will require 2 addresses. The SPI controller can generate an interrupt and that can be attached to the bus IRQ7 via a jumper. The IDE controller uses the SPI interface, so doesn't require any additional addresses.</p>
