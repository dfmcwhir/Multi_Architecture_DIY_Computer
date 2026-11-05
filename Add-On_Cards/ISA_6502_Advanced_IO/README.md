# <h2> Advanced I/O Card</h2>
<p>New card that hasn't been built or tested yet. It has 3 functions:
<ol>SPI Interface</ol>
<ol>CH376 USB module</ol>
<ol>IDE interface</ol></p>

<p> As the schematic shows, most of the components are not populated for use in the DIY ISA computer system. To simplify it even more, the PCB includes a the option to install a CH375 and a bunch of discrete components to use it OR install a CH736 module from Aliexpress (such as: https://www.aliexpress.us/item/3256809583660052.html). So with a module like that plus a GAL and a latch we get a usable USB mass storage system for the computer. Because the original schematic didn't fully decode the address, the card ends up using 8 addresses instead of just the 2 that are required. This will be fixed when the CH376 is implemented on a purpose built card.</p>

<h2> Resources: </h2>
<table><tr><th>Address</th><th>Use</th></tr>
<tr><td>7F20</td><td>CH376 Data port</td></tr>
<tr><td>7F21</td><td>CH376 command port</td></tr>
<tr><td>7F24</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F25</td><td>CH376 command port MIRROR</td></tr>
<tr><td>7F28</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F29</td><td>CH376 command port MIRROR</td></tr>
<tr><td>7F2C</td><td>CH376 Data port MIRROR</td></tr>
<tr><td>7F2D</td><td>H376 command port MIRROR</td></tr>
</table>
