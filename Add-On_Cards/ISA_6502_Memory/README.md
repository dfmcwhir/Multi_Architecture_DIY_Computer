# <h2> 6502 Memory expansion card</h2>
<p>New card that hasn't been built or tested yet. It is currently only planned to be used with the 6502_CPU_Rev2 card. It is possible that in the future other CPU cards can be adapted to use this card as well. When I designed this card, I went for maximum RAM, so consequently it has 16 banks of RAM and only the one bank of ROM selectable by the CPU. My thinking was that I have mass storage options for permanent storage, so I didn't need more ROM. That maybe fine, but I kind of wish I had designed it with more flexibility in mind. Maybe that will for the next revision. Maybe I want to add ROM banks for a cartridge like system for instance. </p>

<p>To enable the memory card the address decoding PLD on the 6502_CPU_Rev2 needs to disable the on-board ROM and RAM (which in the PLD file means commenting out "Block A") and enabling the external memory card (which means uncommenting out "Block B" in the PLD file).</p>

<h2> Populating the memory card</h2>
<p>There is one socket for RAM that can be set via a jumper JP1 to be either an AS6C1008 or AS6C4008 chip. There are 2 ROM sockets for flexibility, but only one can be populated. Socket 2 (32pins), can be a SST39SF010 OR a OneROM can be put in socket 3 (28pins). The OneROM can be configured as either a 27512 (JP3 pins 1-2) or a 23C1000 (JP3 pins 2-3). A 27512 (and possibly other 28 pin ROMs) could also be used in the OneROM socket. The important thing to remember is that only one of the 2 sockets can be populated. Regardless of the which socket or what type of chip is used, only 32K of the ROM will be addressable by the CPU.</p>

<h2> RAM Bank Selection</h2>
<p>The card’s RAM range $0000–$7EFF is split in two:

* $0000–$0FFF: fixed. It’s always bank 0 of the RAM chip, whatever bank is selected, so zero page, the stack and the BIOS variables never disappear.
* $1000–$7EFF: the banked window (about 28K). Which bank you see is set by the bank register.

The bank register sits on the CPU board, in the interrupt GAL at $7FFE. Writing a value 0–15 there puts it on bus lines BA16–BA19. The card’s GAL passes those bits to the RAM chip’s top address lines (RA15–RA18), but only while the address is in the window. In the fixed area it forces them to 0.

Each bank is a 32K slice of the RAM chip: physical address = bank × $8000 + CPU address.

* AS6C4008 (512K): 16 banks (JP1 2–3).
* AS6C1008 (128K): 4 banks (JP1 1–2).

The $0000–$0FFF part of every slice except bank 0 is simply never reached. That’s the price of keeping the address calculation simple. </p>

<h2> Manual ROM bank selection </h2>
<p>The CPU can't select ROM banks, but different banks can be selected manually using jumpers. On the card, JP4 and JP5 choose which 32K image of the ROM chip appears at $8000–$FFFF. A 27SF512-style OneROM image holds 2 of them; the SST39SF010A and the MX23C1000 hold 4. Theoretically we could enable CPU switching of ROM banks by using bodge wires from JP4 and JP5 to the unused pins on the PLD and reprograming the PLD to use BA18-19 to control the ROM bank switching lines we added (RO15-16) instead of RA17-18. That would give us 4 banks of CPU switchable ROM at the expense of reducing us to 4 banks of RAM.</p>
