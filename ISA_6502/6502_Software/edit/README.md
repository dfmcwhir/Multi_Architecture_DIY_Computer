# EDIT: a text editor and markdown viewer

EDIT edits text files on the USB drive, full screen, on the PIC32 display card (80 × 24). Its view mode shows a markdown file formatted, wrapped to the screen.

```
L EDIT 0500
R
```

It asks which file to open. Type a name (`NOTES.MD`), `?` to list the folder, or Enter for a new, empty text. Files are in the monitor's current folder, so use `L DIR` there first, or give a path: `/DOCS/NOTES.MD`.

## Editing

| Key | |
|---|---|
| arrows, Home, End, PgUp, PgDn | move (also ^A / ^E: line start / end, ^Y / ^V: page up / down) |
| ^T, ^B | the top / the bottom of the file |
| Backspace, Del (or ^D) | delete left / right (over a line end too: the lines join) |
| Tab | spaces to the next stop (every 4 columns) |
| ^K | cut the line. ^K again straight after: the next line is added to what was cut |
| ^U | paste what was cut, at the cursor |
| ^F | find (any case), from the cursor on and round to the start. ^N finds the next |
| ^L | go to a line number |
| ^S | save (asks for a name if the text has none) |
| ^W | save as (the new name is then the file's) |
| ^O | open another file |
| ^R | view mode |
| ^G | help |
| ^Q | quit to the menu (asks first if the text was changed) |

The bottom line shows the file's name, `(changed)` once you have typed, the line (of how many) and the column. Messages show there until the next key.

Lines longer than the screen scroll sideways when the cursor goes past the edge.

## View mode (^R)

The text wrapped at word boundaries, read-only. A `.MD` file (or one with no extension) is shown formatted:

| Markdown | Shown as |
|---|---|
| `# Heading` | bold, reverse |
| `## Heading` | bold, underlined |
| `### Heading` and smaller | bold |
| `**bold**`, `__bold__` | bold |
| `*emphasis*`, `_emphasis_` | underlined (the display has no italics) |
| `` `code` `` | reverse |
| `[text](address)`, `![alt](picture)`, `<http://...>` | the text underlined, the address hidden |
| `- item`, `* item`, `+ item` | a bullet, wrapped rows indented under the text |
| `1. item` | the number, wrapped rows indented |
| `> quote` | a bar down the left |
| `---`, `***`, `___` | a line across the screen |
| ```` ``` ```` blocks, and lines indented 4 spaces | as they are, indented, not wrapped at words |
| tables (`| a | b |`) | with box lines; not wrapped (what doesn't fit is cut off) |
| `\*` | a plain `*` |
| HTML tags (`<br>`, `<b>`) | hidden |
| `~~struck~~` | plain (the display can't strike through) |

| Key | |
|---|---|
| Up, Down (or j, k) | a row |
| PgUp, PgDn (or B, Space) | a page |
| Home, End | the start / the end |
| M | markdown formatting off / on (to see a `.MD` file as it is, or a `.TXT` formatted) |
| Esc or ^R | back to editing. If you scrolled, the cursor goes to the line at the top of the view |

## Large files (view only)

A file too big to edit (over about 13 KB) can still be read. EDIT asks `View it? (Y/N)`. With Y the file opens in view mode, read-only, up to 16 MB:

- EDIT holds a window of about 13 KB of the file. When you scroll near either end of it, the part far behind is dropped and the next piece is read from the stick. Scrolling looks the same as with a small file; a page takes about 0.3 s, or about 0.8 s when it has to read the next piece.
- The status line shows where you are: `Line 1234  37/120 KB`. Line numbers are counted as you scroll from the start. After End (about 1.2 s) they aren't known, so the status shows `Line ?` until you go back to the start with Home.
- The file is never written. ^S and Esc just say it is view only. ^O opens another file, ^Q quits.
- One limit: a ``` code block that starts before the window's start and ends inside it can be shown as ordinary text after you jump with End. Scrolling from the start always gets it right.

## Notes

- **Size:** up to about 13 KB of text to edit, plus a 2 KB clipboard. A bigger file can be viewed (below), not edited; it is never cut short.
- **Line ends:** text is kept with LF line ends. A file read with CR LF is saved with CR LF, and new files are saved with CR LF too, so Windows editors show them right. A file with LF only is saved with LF.
- **Characters:** UTF-8 is shown as the nearest character the display has (its CP437 set): accented letters, dashes, curly quotes, bullets, box lines, some symbols. Other characters show as `?`. They are kept as they were when the file is saved. Bytes that aren't UTF-8 are shown as CP437 characters.
- **Speed (2 MHz), measured in the emulator on a 12 KB file:** a key takes about 0.02 s, however long the file. Keys typed faster than the screen redraws are all taken, and the screen catches up once. Opening the file takes 1.5 s. Going into view mode (or back) takes about 0.7 s, because the whole text is moved in memory first. A page in view mode takes about 0.6 s.
- **The display:** EDIT uses ANSI codes only: cursor position, erase to the end of the line, bold, underline, reverse, and insert / delete line to scroll a row. If your display card doesn't do insert / delete line, build with `-D USE_SCROLL=0` (it then redraws instead). For another screen size, `-D ROWS=..` and `-D COLS=..`.
- EDIT never writes the last column of the screen, so the display never wraps or scrolls by itself.

## Building and testing

`make.bat` (Windows) or `sh b.sh` builds `EDIT.BIN`. It needs `sbc_api.inc` one folder up, and `ay/ch376r.s` (the USB drive code) from the `ay` folder next to it.

`test/test_edit.py` runs EDIT in the emulator (py65), with the CH376 model from `ay/test/sim.py` (a folder on the PC as the USB drive) and a model of the screen. It opens, edits and saves files, scrolls, finds, cuts and pastes, and checks the view mode's formatting row by row. It also checks that what the screen shows after many small updates is the same as a full redraw. `test/test_big.py` pages through a 111 KB file and a large markdown file, both ways, checking every screen against the file.

```
PY65=path/to/py65 python3 test/test_edit.py
PY65=path/to/py65 python3 test/test_big.py
```
