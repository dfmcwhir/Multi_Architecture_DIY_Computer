<h1> ISA_6502_IO card</h1>
<p>6522 based IO card. Also has PCF8584 I2C interface. Primarily used for timers for the sound card routines and interface for the NES gamepad, so it is required for a lot of games and software.</p>

<h2>Known Bugs</h2>
  <li>The footprints for the resistors are too small so they have to be installed at an angle. </li>
  <li>The PCF8584 has jumpers to connect the SDA and SCL I2C signals to the bus on what were previously unused pins. Those pins are now used for other signals, so those jumpers should never be installed. The I2C interface is still available on the header pins on the card.</li>

<h2>Resources</h2>
<table><thead><tr><th>Address</th><th>Function</th></tr></thead>
<tr><td>7F00</td><td>PORTB</td></tr>
<tr><td>7F01</td><td>PORTA</td></tr>
<tr><td>7F02</td><td>DDRB</td></tr>
<tr><td>7F03</td><td>DDRA</td></tr>
<tr><td>7F04</td><td>T1C LOW</td></tr>
<tr><td>7F05</td><td>T1C HIGH</td></tr>
<tr><td>7F06</td><td>T1L LOW</td></tr>
<tr><td>7F07</td><td>T1L HIGH</td></tr>
<tr><td>7F08</td><td>T2C LOW</td></tr>
<tr><td>7F09</td><td>T2C HIGH</td></tr>
<tr><td>7F0A</td><td>SR</td></tr>
<tr><td>7F0B</td><td>ACR</td></tr>
<tr><td>7F0C</td><td>PCR</td></tr>
<tr><td>7F0D</td><td>IFR</td></tr>
<tr><td>7F0E</td><td>IER</td></tr>
<tr><td>7F0F</td><td>ORA/IRA</td></tr>
</table>

6522 = IRQ2
PCF8584 = IRQ4
