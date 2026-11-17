# PICOTEST: the PICO9918's F18A features for SMB

`L PICOTEST 0800`, then `R`. SPACE pauses the scroll, Q quits.

What you should see:
1. **The top line stays put:** "LAYER 2: FIXED. SCROLL xxx" (tile layer 2, white on black). The number counts 000-1FF and wraps.
2. **Everything below scrolls left smoothly,** a pixel a frame, without jumps:
   - the two number rows (the column numbers 00-63);
   - the yellow letters on blue;
   - the red bricks.

   Check the moments the number passes 100 and 000, when the page bit flips. Columns 63 and 00 should join seamlessly.
3. **All 12 coloured balls show on one line,** bobbing together. Magnified 8 × 8 sprites, with the sprites-per-line limit raised to 31.
