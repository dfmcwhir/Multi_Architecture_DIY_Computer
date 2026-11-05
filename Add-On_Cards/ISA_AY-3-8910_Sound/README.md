#<h2>AY-3-8910 sound card</h2>

<p>This a new card that hasn't been built or tested yet. However, a rev0 of the AY-3-8910 portion of this card was built and tested on a prototyping board and worked for sound. For this version of the card the I/O ports A and B were broken out and can be used for general purpose IO. The SPO256 speech chip was added to this version of the board as well.</p>

<h2>Known Bugs</h2>
<p>
  <li>Rev0 of this card ran fine at 2MHz, but to make this card capable of running at higher clock speeds, the PLD introduce a /WAIT signal. For the 6502_CPU_Rev2 card that means the J1 Wait_Sel jumper should be on pins 2-3. However, on the 8085 and Z80 cards that won't work. The current 8085 CPU card doesn't have the /WAIT or /STRETCH signals implemented at all. For the Z80 card, the fix is to cut the trace to pin1 of the PLD and attach pin1 of the PLD to the TC (2XOSC) pin on the bus. That modification should also still work when using the 6502_CPU_Rev2 but with JP1 Wait_Sel set to pin 1-2. To make it work with the current 8085 card, it probably requires keeping CPU speed <3MHz and updating the PLD to not use the /WAIT logic. My current 8085 card uses a 4.9152MHz crystal so the clock is ~2.45MHz, but I haven't tested it with the sound card yet. </li></p>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F22</td><td>AY3 Command Register</td></tr>
<tr><td>7F23</td><td>AY3 Data Register</td></tr>
<tr><td>7F26</td><td>SPO256 command/status register</td></tr>
</table>

<p>The SPO256 can use IRQ7 but installing a jumper, but it isn't clear if that will be necessary or desirable.</p>
