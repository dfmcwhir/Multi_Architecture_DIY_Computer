<h1> 6502 CPU rev1 card</h1>
<p>The initial idea was to make modular version of Ben Eater's breadboard 6502 on a PCB. Really there isn't a lot left of Ben's design. This is the card that all of the software in the 6502_Software folder was made for and tested on.</p>

<h2>Known Bugs</h2>
<p>
  <li>I followed the logic Ben used to create a /DMA signal which combines the RDY and BE pins on the 6502. So far, I haven't made anything that needed to use the /DMA pin, but it has become clear that if I speed up the CPU card, some add-on cards will need to be able to stop the CPU with the ready pin, but not disable the busses with the BE pin. Everything works at the current speed (2MHz), but if I were to try to go to 4MHz (6MHz?) I would need to cut the trace between the BE and RDY pins, add another pull up resistor, and bodge a wire to the RDY pin from a bus signal so that add-on cards can have the CPU wait from them. These are fixes that are already planned for on the Rev2 card. </li>
  <li>When I copied priority interrupt encoder circuit, the order of the interrupts was accidently reversed from the original circuit. This is an easy fix in software and I'm not likely to fix it. I didn't really plan out which interrupt should be higher or lower than others when I assigned them to add-on cards anyway and changing all the add on card's hardware would be a pain.  </li></p>

<h2> Specs: </h2>
<li>Speed: 2MHz (would probably be ok at 3mhz, maybe 4mhz)</li>
<li>RAM: just under 32K is addressable</li>
<li>ROM: 32K</li>
<li>I/O: up to 255 addresses</li>

<h2>Current Memory Map</h2>
<table><thead><tr><th>AddressPin</th><th>Function</th></tr></thead>
<tr><td>0000</td><td>Ram begin</td></tr>
<tr><td>7EFF</td><td>Ram end</td></tr>
<tr><td>7F00</td><td>IO card 65C22 begin</td></tr>
<tr><td>7F0F</td><td>IO card 65C22 end</td></tr>
<tr><td>7F10</td><td>IO card I2C begin</td></tr>
<tr><td>7F11</td><td>IO card I2C end</td></tr>
<tr><td>7F12</td><td>Undefined</td></tr>
<tr><td>7F13</td><td>Undefined</td></tr>
<tr><td>7F14</td><td>Serial card begin</td></tr>
<tr><td>7F17</td><td>Serial card end</td></tr>
<tr><td>7F18</td><td>Display/KB address begin</td></tr>
<tr><td>7F1B</td><td>Display/KB address end</td></tr>
<tr><td>7F20</td><td>CH376 Data port</td></tr>
<tr><td>7F21</td><td>CH376 command port</td></tr>
<tr><td>7F22</td><td>AY-3-8910 CMD</td></tr>
<tr><td>7F23</td><td>AY-3-8910 DATA</td></tr>
<tr><td>7F24</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F25</td><td>CH376 command port MIRROR</td></tr>
<tr><td>7F26</td><td>SPO256A-AL2</td></tr>
<tr><td>7F27</td><td>Undefined</td></tr>
<tr><td>7F28</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F29</td><td>CH376 command port MIRROR</td></tr>
<tr><td>7F2A</td><td>Undefined</td></tr>
<tr><td>7F2B</td><td>Undefined</td></tr>
<tr><td>7F2C</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F2D</td><td>CH376 command port MIRROR</td></tr>
<tr><td>7F2E</td><td>Spare IO addresses begin</td></tr>
<tr><td>7FFE</td><td>Spare IO addresses End</td></tr>
<tr><td>7FFF</td><td>Interrupt Register</td></tr>
<tr><td>8000</td><td>Rom begin</td></tr>
<tr><td>FFFF</td><td>Rom end</td></tr>
</table>

<h2> Add-On Cards </h2>
<p>All the cards that have been built so far have been tested and work on the rev1 CPU card at 1MHz and 2MHz.</p>

<h1> 6502 CPU rev2 card</h1>

<p>This is the new card that has been ordered, but not built or tested yet. New features/changes:
<li> It should be compatible with all the existing add-on cards, at least at the current 2MHz speed. It is unknown what will happen with a faster CPU card.</li>
<li> New bus signals so add-on cards can stop the CPU (/wait) or stretch the clock (/stretch) if necessary. This change also requires a the Western Digital W65C02 version of the 6502.</li>
<li> The /DMA signal (on the /DRQ2 bus pin) should also work to stop and isolate the bus, but until a make a card that actually uses DMA, its hard know if there are issues or not.
<li> Utilizes previously unused bus address pins A16-19 to enable memory bank switching on an external memory card. Should allow for up to 16 banks of 32KB of memory. The Rev2 board also kept the sockets for the RAM and ROM onboard so the CPU can run without the memory expansion board, but it will require PLD update and it can't used with the expansion memory installed.</li>
<li> Switched to faster ATF22v10C-7 PLDs (part of trying to make it run faster</li>
<li> As part of the /wait and /stretch changes, the CPU is now clocked through a flip-flop and the CPU will run at half of the oscillator frequency (i.e. to run the CPU at 4MHz I will need to install an 8MHz oscillator).</li>
<li> The MEMw and MEMr bus signals are no longer truly only for memory reads and writes. They are now /WE and /RD signals, meaning they will be active during IO read and write operations, not just memory reads and wries like on rev1 of the card. So any future add on cards that need true MEMr and/or MEMw signals will need to decode them locally.</li></p>

<p> I'm hoping that with all the changes I will be able to get the CPU speed up to 4,6, or possibly even 8MHz.</p>
