# <h2> Advanced I/O Card</h2>
<p>New card that is in the process of being tested. So far, the USB interface definitely seems to be working. The SPI and IDE interfaces are probably working, but due to a mistake while assembling I installed a connector backwards and burned up my CF card so I haven't fully tested it. It has 3 functions:
<ol>1. SPI Interface</ol>
<ol>2. CH376 USB module</ol>
<ol>3. IDE interface</ol></p>

<p>The SPI and IDE interface essentially the same circuits and firmware that Daryl Rictor created. Documented here: https://sbc.rictor.org/65spi2.html and here: https://sbc.rictor.org/ide.html. The only real differences are a small change in the ide circuit and firmware to use an ATMEGA32 instead of an ATMEGA324 and using a DS1302 RTC module instead of a discrete DS1302 chip and supporting components.</p>

<p>The SPI controller will require 4 addresses (Exact addresses TBD, but will likely use some of the addresses freed from replacing the old CH376 USB card) and the USB controller will require 2 addresses. The SPI controller can generate an interrupt and that can be attached to the bus IRQ7 via a jumper. The IDE controller uses the SPI interface, so doesn't require any additional addresses.</p>

<h2>Known Issues:</h2>
<li> The IDE header/connector is close to the ATMEGA32. To get the pins to line up with an IDE cable, the connector/header needs to be installed on the back of the board. The silkscreen should be updated. Pin1 is marked, verify pinout before connecting a drive.</li>
<li> Should add a 10k pull-down resistor IDE connector pin 3, possibly with a jumper. This is so it isn't floating when a drive isn't attached. Without this you can't read the RTC through the IDE controller when a drive isn't attached. </li>
