#<h2> ISA_6502_Serial_Rev3 </h2>
<p>This is a new card that hasn't been built or tested yet. It has the same 6551 ACIA chip and MAX232 serial interface, but now a PS2 keyboard and mouse interface has been moved to this board. The keyboard and mouse interfaces to the bus using an ATMEGA328 microcontroller. The code for the ATMEGA238 is based on Grant Searle code here: http://searle.x10host.com/MonitorKeyboard/index.html. The ATMEGA also provides a TTL serial console interface that can be read from and written to. This is for providing a UI when you don't have a keyboard and display hooked up to the computer without having to dedicate the card's main serial interface to that.</p>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F14</td><td>Serial Data Register</td></tr>
<tr><td>7F15</td><td>Serial Status Register</td></tr>
<tr><td>7F16</td><td>Serial Command Register</td></tr>
<tr><td>7F17</td><td>Serial Control Register</td></tr>
<tr><td>7F1E</td><td>Read=KB/mouse data, Write=serial console out/td></tr>
<tr><td>7F1F</td><td>Read=KB status, D7=KBavail,D6=DBusy</td></tr>
</table>

<p>The 6551 uses IRQ3. The keyboard/mouse uses IRQ5 or 6 (selectable by a jumper). Previously, when the kb and the display were on one card it used IRQ5, but jumper allows for more flexibility.</p>
