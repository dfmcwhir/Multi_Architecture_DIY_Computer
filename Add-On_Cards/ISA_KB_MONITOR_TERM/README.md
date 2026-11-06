<h1> ISA_KB_MONITOR_TERM card</h1>
<p>This is the primary display and kb card I have been using with the system so far (with the 6502 CPU Rev1 and 8085 CPU cards). The circuit is basically this https://geoffg.net/terminal.html made by Geoff Graham connected to a 6551 ACIA serial chip connected to the ISA Bus. So, it is a parallel to serial to VGA circuit which limits the speed of the display. To help make it more useful for the video games in the 6502_Software folder, the firmware has been modified to add extended graphic characters and to add some functions for telling the display to repeat a character or block of characters a specific number of times. This reduces the number of bytes that has to be written to the display card. It is functional, but monochrome and limited in the graphic capabilities. Hopefully it will be replaced by one of the other video cards that I am making.</p>

<h2>Known Bugs</h2>
<p>
  <li>I have added a bodge wire between the /DSR, /DCD, and ground on the 6551 (pins 16,17,1) to prevent inadvertent triggering of interrupts. That is based on an old Ben Eater video on his serial interface.</li></p>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F18</td><td>Data Register</td></tr>
<tr><td>7F19</td><td>Status Register</td></tr>
<tr><td>7F1A</td><td>Command Register</td></tr>
<tr><td>7F1B</td><td>Control Register</td></tr>
</table>

IRQ5
