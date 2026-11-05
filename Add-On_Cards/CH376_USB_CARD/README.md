# <h2> CH376 (or CH375) USB Card </h2>
<p>This is the a very rare case where a Standard PC ISA card is able to be used for this DIY system... Sort of. I made this card that had and XTIDE option ROM, a DiskOnChip module, and an CH375 (or CH376) USB chip to be used on XT class PCs (That project is here: https://github.com/dfmcwhir/ISA_CH37X_XTIDE_DoC_combo_card). When looking at it, I realized that if I just didn't populate the option ROM and DiskOnChip Module and re-programed the PLD to change the address range, then I could fit it into the DIY ISA computer system. </p>

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
