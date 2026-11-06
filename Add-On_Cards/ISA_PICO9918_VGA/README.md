<h2>ISA_PICO9918_VGA</h2>

<p>This a new card that hasn't been built or tested yet. It is based on the around the PICO9918 PRO 2.0 chip (https://www.arcadeshopper.com/wp/store/#!/Pico9918-PRO-v2-0-VDP-VGA/p/825096573 and https://github.com/visrealm/pico9918 ) which is a pin compatible replacement for a TMS9918 VDP chip used in old computers emulated in a PiPico with VGA output. Because I planned for this card to replace my current kb and display adapter, I added an atmega328 based keyboard and mouse interface to this card also. I have since put a keyboard/mouse interface on to my rev3 serial card, which will free up space on this card later. So in the next version of this card, I want to include the rest of the circuit that would be required to use a real TMS9918 chip with a composite video output or use the PICO9918 with vga output. </p>

<h2>Features:</h2>
<li>Display: 640x480 @ 60 Hz progressive.</li>
<li>Input: PS/2 keyboard and mouse.</li>
<li>TTL serial console header pins for a serial UI when a display and/or kb is not attached to the computer.</li>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F1C</td><td>Pico9918 VRAM Register</td></tr>
<tr><td>7F1D</td><td>Pico9918 Status Register</td></tr>
<tr><td>7F1E</td><td>KB/Mouse Data Register</td></tr>
<tr><td>7F1F</td><td>KB/Mouse Status Register</td></tr>
</table>

<p>The display and kb circuits each have a jumper to set their interrupt to either 5 or 6, so the display can be set to one IRQ and the kb/mouse can be set to the other.</p>
