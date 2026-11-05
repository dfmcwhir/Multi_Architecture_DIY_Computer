<h2> 8085 CPU rev1 card</h2>
<p>The initial hardware was derived/simplified from https://github.com/skiselev/minimax8085/tree/master. Since there is a separate serial card, that portion of the circuit was removed. I also added the IRQ priority encoder and register (the same as on my other CPU cards) from here https://6502.org/mini-projects/priority-interrupt-encoder/priority-interrupt-encoder.html . However, I connected the interrupt encoder to the CPU incorrectly, see the hardware bugs below.</p>

<h2>Known Bugs</h2>
<p> * On my initial PCB, the INTR line from the prioroity encoder was connected to the INTR pin on the 8085 and it needed to be connected to the RST 6.5 pin instead. The fix is to cut the trace going to pin 10 of the 8085 and connect a bodge wire from the GAL U7 pin 11 (/INTR) to pin 8 (RST6.5) of the 8085.
  * The 100K resister R2 in the reset circuit is supposed to be a pullup for the reset circuit. But on this PCB R2 was missing the connection to the reset pin (pin 36 on the 8085) and the rest of the reset circuit. The fix is to tie end of R2 that is connected to C2 to reset line. The easiest place to do that is at the junction of D1 and R1. </p>

<h2> Add-On Cards </h2>
<p>The 8085 has been tested with the 6522 portion of the I/O card, the serial card, and the KB_AND_MONITOR card. </p>
