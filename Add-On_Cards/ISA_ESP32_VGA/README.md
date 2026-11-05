<h2>AY-3-8910 sound card</h2>

<p>This a new card that hasn't been built or tested yet. It is based on the FABGL ESP32 library here: https://github.com/fdivitto/fabgl. That is an older library and that theoretically could provide VGA video as well as KB, mouse and sound. The firmware is here is an AI generated first draft of an 8-bit parallel interface to the ESP32/FABGL library which isn't the way that it seems like most people used that library. It could be fun to use and expand on this system. It definitely seems like it could be used to offload a fair amount processing from the 6502 in terms of generating graphics and UI interaction. The downside is that it is pretty slow. According to the AI analysis, even at a 2MHz CPU speed this card will require using the CPU /WAIT signal. Not sure how/if this will work with the 8085 or Z80 cpu cards. We will see how it goes.</p>

<h2>Features:</h2>
<li>Display: 640×480, 64 colours, with your FabGL-style 2-resistor ladders. It has an 80×30 text layer with a redefinable font (usable for tiles), a 320×240 bitmap with drawing commands and scrolling, and 16 sprites plus a mouse pointer.</li>
<li>Input: PS/2 keyboard and mouse, plus USB keyboards and mice on the S3’s own USB port (hubs and wireless combo receivers work).</li>
<li>Sound: a 4-voice synthesizer.</li>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F18</td><td>Display Status/Command Register</td></tr>
<tr><td>7F19</td><td>Display Data Register</td></tr>
<tr><td>7F1A</td><td>KB/Mouse/Sound Command/Status Register</td></tr>
<tr><td>7F1B</td><td>KB/Mouse/Sound Data Register</td></tr>
</table>

<p>This card can use either IRQ5 or 6 settable by a jumper.</p>
