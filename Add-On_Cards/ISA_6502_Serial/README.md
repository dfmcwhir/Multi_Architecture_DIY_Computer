<h1> ISA_6502_Serial card</h1>
<p>This is the original version of the serial card that only has the 6551 ACIA chip on it.</p>

<h2>Known Bugs</h2>
<p>
  <li>The footprint for the 9-pin connector is for the female connector. I think I wanted to use the male 9-pin connector here. You use a male 9-connector, but you need to place it on the backside (solder side) of the board and solder it on the component side. Or you can place a female connector on component side and use a 9-pin gender changer if necessary.</li></p>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F14</td><td>Data Register</td></tr>
<tr><td>7F15</td><td>Status Register</td></tr>
<tr><td>7F16</td><td>Command Register</td></tr>
<tr><td>7F17</td><td>Control Register</td></tr>
</table>

IRQ3
