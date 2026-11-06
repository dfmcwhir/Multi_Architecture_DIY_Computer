# Multi_Architecture_DIY_Computer
A DIY computer system that uses a common backplane with swappable 8-bit CPU and add-on cards<BR><br>

Up front, I will state the following:
  1. I started the project for my own learning and enjoyment. There will be documentation shortfalls and hardware and SW bugs that I missed and/or fixed and forgot about. There will also be plenty of poor design choices and probletunities for improvement. 
  2. Most of the electrical designs borrow ideas/circuits from other peoples work and I have modified them to work in my systems. I will try to make sure I document where I got what from.
  3. For the software and firmware, initially I was doing my own development, but I'm not a coder so I progress was really slow/non-existent. More recently, I have started using AI which has led to a lot of progress and really all the working code on this site.

<br>
<h2> The Concept </h2>
The initial idea as I wrote it in my notes app was:<br>
<quote>
  <b><i></i>Idea for a retro computer "system" that uses various cards in the ISA format with a passive ISA back plane. Ideally the most of the individual ISA cards will be less that 100mmx100mm for cheaper PCB prices which limits them to 8-bit isa cards.

Ideally cpu and interface cards should be inter changeable, so that interface cards can be used with multiple different types of CPU boards. That may require jumpers/switches to change logic level of some control signals and/or to set address decoding.

Possible CPU cards:
  - 6502 - Based on Ben Eater's design
  - 8085 - Similar to the MiniMax 8085?
  - 8088 - IBM XT compatible-ish
  - 6809 - based on Grant Searle's design 
  - Z80 - TRS-80 compatible?
  - ESP32 - For giggles - Would need some sort of multiplexing/latching to generate the data, address, and control busses from the GPIO pins
  - ATMEGA328? - For giggles - Would need some sort of multiplexing/latching to generate the data, address, and control busses from the GPIO pins 

Possible interface cards:
  - Retro video card - MC6847 based. Similar to Kiran Tomlinson's blog post
  - Atmel based keyboard/display/serial - Based on Grant Searle's design
  - Memory expansion
  - Storage controller - ideally the overall system would be compatible with the PicoMem I/O card but a dedicated storage controller maybe required/desired.
</b></i>
</quote>
<br>
So far I have done the 6502 and 8085 CPU cards with the Z80 on the way. The plans for the add-cards changed over time, I didn't do all the ones listed (yet), but I have a number of others. Most of them have ISA_6502 in the name, because that is the CPU I started with, but should at least theoretically be compatible with other CPU cards if they are designed to interface with the bus as I have defined it and with the correct software.

<h2> The "ISA" Bus </h2>
<p>To make it very clear, I am using the physical ISA bus for interfacing but in no way indicating that it meets any ISA specification or standards. Putting a normal ISA card into the system will almost definitely not work and may damage everything. </p>
<p>With that out of the way, when I started designing the system, I tried to match the functions of the signals of my card to the signals functions/names of the standard ISA bus. The idea being, that it would make it easier to insure CPU card compatibility with the add-on cards that way. The matching to the standard ISA pin functions has drifted over time.</p>

<H2>Current bus description</H2>
<table><thead><tr><th>Pin</th><th>Name</th><th>Dir</th><th>Description</th></tr></thead><tbody>
<tr><td>A1</td><td>/I/O CH CK</td><td>IN</td><td>/IOen. Active low; indicates an I/O operation</td></tr>
<tr><td>A2</td><td>D7</td><td>IN/OUT</td><td>Data bit 7</td></tr>
<tr><td>A3</td><td>D6</td><td>IN/OUT</td><td>Data bit 6</td></tr>
<tr><td>A4</td><td>D5</td><td>IN/OUT</td><td>Data bit 5</td></tr>
<tr><td>A5</td><td>D4</td><td>IN/OUT</td><td>Data bit 4</td></tr>
<tr><td>A6</td><td>D3</td><td>IN/OUT</td><td>Data bit 3</td></tr>
<tr><td>A7</td><td>D2</td><td>IN/OUT</td><td>Data bit 2</td></tr>
<tr><td>A8</td><td>D1</td><td>IN/OUT</td><td>Data bit 1</td></tr>
<tr><td>A9</td><td>D0</td><td>IN/OUT&gt;</td><td>Data bit 0</td></tr>
<tr><td>A10</td><td>I/O CH RDY</td><td>IN</td><td>IOrdy or /WAIT, pulled low to lengthen memory cycles or pause the CPU (depending on the CPU card)*</td></tr>
<tr><td>A11</td><td>AEN</td><td>OUT</td><td>Address enable; Not currently used</td></tr>
<tr><td>A12</td><td>A19</td><td>OUT</td><td>Address bit 19 or BA19; Used for memory bank selection</td></tr>
<tr><td>A13</td><td>A18</td><td>OUT</td><td>Address bit 18 or BA18; Used for memory bank selection</td></tr>
<tr><td>A14</td><td>A17</td><td>OUT</td><td>Address bit 17 or BA17; Used for memory bank selection</td></tr>
<tr><td>A15</td><td>A16</td><td>OUT</td><td>Address bit 16 or BA19; Used for memory bank selection</td></tr>
<tr><td>A16</td><td>A15</td><td>OUT</td><td>Address bit 15</td></tr>
<tr><td>A17</td><td>A14</td><td>OUT</td><td>Address bit 14</td></tr>
<tr><td>A18</td><td>A13</td><td>OUT</td><td>Address bit 13</td></tr>
<tr><td>A19</td><td>A12</td><td>OUT</td><td>Address bit 12</td></tr>
<tr><td>A20</td><td>A11</td><td>OUT</td><td>Address bit 11</td></tr>
<tr><td>A21</td><td>A10</td><td>OUT</td><td>Address bit 10</td></tr>
<tr><td>A22</td><td>A9</td><td>OUT</td><td>Address bit 9</td></tr>
<tr><td>A23</td><td>A8</td><td>OUT</td><td>Address bit 8</td></tr>
<tr><td>A24</td><td>A7</td><td>OUT</td><td>Address bit 7</td></tr>
<tr><td>A25</td><td>A6</td><td>OUT</td><td>Address bit 6</td></tr>
<tr><td>A26</td><td>A5</td><td>OUT</td><td>Address bit 5</td></tr>
<tr><td>A27</td><td>A4</td><td>OUT</td><td>Address bit 4</td></tr>
<tr><td>A28</td><td>A3</td><td>OUT</td><td>Address bit 3</td></tr>
<tr><td>A29</td><td>A2</td><td>OUT</td><td>Address bit 2</td></tr>
<tr><td>A30</td><td>A1</td><td>OUT</td><td>Address bit 1</td></tr>
<tr><td>A31</td><td>A0</td><td>OUT</td><td>Address bit 0</td></tr>
<tr><td>B1</td><td><abbr title="Ground">GND</abbr></td><td>Ground</td><td></td>
</tr><tr><td>B2</td><td>RESET</td><td>OUT</td><td>Active low to reset or initialize system logic</td></tr>
<tr><td>B3</td><td>+5V</td><td>+5 <abbr title="Volts Direct Current">VDC</abbr></td><td></td></tr>
<tr><td>B4</td><td>IRQ2</td><td>IN</td><td>Interrupt Request 2; I/O card </td></tr>
<tr><td>B5</td><td>-5VDC</td><td>-5 VDC</td><td>Not Currently used</td></tr>
<tr><td>B6</td><td>DRQ2</td><td>IN</td><td>/DMA; Not used/tested by any add-on cards yet, but should put CPU in state for DMA operations*</td></tr>
<tr><td>B7</td><td>-12VDC</td><td>-12 VDC</td><td>Not Currently used</td></tr>
<tr><td>B8</td><td>/NOWS</td><td>IN</td><td>/STRETCH (CLK stretch); When Low should slow down the clock*</td></tr>
<tr><td>B9</td><td>+12VDC</td><td>+12 VDC</td><td>Not Currently used</td></tr>
<tr><td>B10</td><td>GND</td><td>Ground</td><td></td></tr>
<tr><td>B11</td><td>/SMEMW</td><td>OUT</td><td>Originally intended as /MEMw, but may now be a general Write*</td></tr>
<tr><td>B12</td><td>/SMEMR</td><td>OUT</td><td>Originally intended as /MEMr, but may now be a general Read*</td></tr>
<tr><td>B13</td><td>/IOW</td><td>OUT</td><td>/IOw (/IOen + /Write)*</td></tr>
<tr><td>B14</td><td>/IOR</td><td>OUT</td><td>/IOr (/IOen + /Read + Clk)*</td></tr>
<tr><td>B15</td><td>/DACK3</td><td>OUT</td><td>Not currently used</td></tr>
<tr><td>B16</td><td>DRQ3</td><td>IN</td><td>Not currently used</td></tr>
<tr><td>B17</td><td>/DACK1</td><td>OUT</td><td>Not currently used</td></tr>
<tr><td>B18</td><td>DRQ1</td><td>IN</td><td>Not currently used</td></tr>
<tr><td>B19</td><td>/REFRESH</td><td>IN/OUT</td><td>Not currently used</td></tr>
<tr><td>B20</td><td>CLOCK</td><td>OUT</td><td>/CLK (inverted clock)</td></tr>
<tr><td>B21</td><td>IRQ7</td><td>IN</td><td>Interrupt Request 7, Possibly sound card or SPI interface</td></tr>
<tr><td>B22</td><td>IRQ6</td><td>IN</td><td>Interrupt Request 6; Possibly display/kb</td></tr>
<tr><td>B23</td><td>IRQ5</td><td>IN</td><td>Interrupt Request 5; Usually KB/Display</td></tr>
<tr><td>B24</td><td>IRQ4</td><td>IN</td><td>Interrupt Request 4; I/O card I2C interface</td></tr>
<tr><td>B25</td><td>IRQ3</td><td>IN</td><td>Interrupt Request 3; Serial Card</td></tr>
<tr><td>B26</td><td>/DACK2</td><td>OUT</td><td>Not currently used</td></tr>
<tr><td>B27</td><td>T/C</td><td>OUT</td><td>Raw oscilator clock (2 x CLK) on some CPU cards(</td></tr>
<tr><td>B28</td><td>ALE</td><td>OUT</td><td>Not currently used</td></tr>
<tr><td>B29</td><td>+5V</td><td>+5 VDC</td><td></td></tr>
<tr><td>B30</td><td>OSC</td><td>OUT</td><td>CLK used by CPU and most circuits. In some CPU cards it is 1/2 of the osc frequency</td></tr>
<tr><td>B31</td><td>GND</td><td>Ground</td><td></td></tr>
<tr><td></td><td></td><td></td><td></td></tr>
</tbody></table>
<h3>Notes about some signals:</h3>
<p> /MEMw and /MEMr were initially derived from the R/nW signal on the 6502 card and either /ROMen or /RAMen. As things got more complex, it became necessary to have read and write signals that were available during I/O operations (/IOen) but were not connected to the clock. So now /MEMw and /MEMr on the bus could (depending on the CPU card) be active anytime either an I/O or Memory operation is happening. This means that add-on cards, if a memory read or write is needed, the /MEMw and MEMr signals should be qualified as being in memory by the address or at least by /IOen not being active.</p>
<p>The way /IOr is used on some add-on cards requires it to be active only when the CLK is high, so that is the way it is decoded on the bus. If a read from I/O that isn't dependent on the CLK being high is required (also required on some cards) then a local /read should be decoded from the /IOen and MEMr or /IOen and /IOw not active. /IOw is independent from the clk</p>
<p>Initially the /DMA (/DRQ2) signal was provided for simple DMA operations that Ben Eater describes for his VGA card implementaion. I have never used it and it maybe incompatible with some CPU cards.</p>
<p>IOrdy (or /WAIT) and /STRETCH were implemented on the 6502 CPU Rev2 card and haven't been tested yet. The difference is that /WAIT stops the CPU but CLK and /CLK continue to run. /Stretch stops CLK and /CLK. An Add-card would assert /Stretch then use the TC (2XOSC) raw oscillator signal to count some number of cycles before de-asserting it. On some CPU cards neither signal is implemented at all (like the 8085 CPU Rev1) and on others (like the Z80 CPU rev1) /STRETCH and /WAIT are the same (both are /STRETCH). I don't think any cards require these signals/features if operated at <4MHz. </p>
