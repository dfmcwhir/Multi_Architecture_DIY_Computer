"""Test TALK.BIN in the emulator against tts_ref.py: each line typed must
send exactly the reference's allophones to SBC_SAY (+ the ROM's PA4).
Also /A, /P, /F (a text file, several chunks), no chip.   python test_talk.py"""
import sys, os, random
sys.path.insert(0, '/home/claude/tools')
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import emu6502, tts_ref

problems = []
def check(c, what):
    print(('ok    ' if c else 'FAIL  ') + what)
    if not c: problems.append(what)

def machine(spo=True):
    m = emu6502.Machine(int(os.environ.get('MHZ', '4')))
    m.spo = spo
    m.drives = {'U': os.path.join(HERE, 'test_disk'), 'C': None}
    m.load(os.path.join(HERE, 'TALK.BIN'), 0x800)
    m.said = []
    m.run(frames=5)
    return m

def typed(m, text, frames=None):
    m.said = []; m.out = []
    for ch in text + '\r': m.key(ch)
    m.run(frames=frames or (20 + len(text) // 2))
    return bytes(m.out).decode('latin1')

def ref(text):
    t, ph = tts_ref.to_phonemes(text)
    return [tts_ref.CODE[a] for a in tts_ref.allophones(ph)] + [3]

def names(codes): return ' '.join(tts_ref.AL[c] for c in codes)

m = machine()
out = bytes(m.out).decode('latin1')
check('TALK' in out and 'No SPO256' not in out, 'starts, chip found')
LINES = [
    'Hello world.',
    'This is the 6502 talking.',
    'I have 100 apples, 3 pears and 65535 grapes!',
    'The quick brown fox jumps over the lazy dog.',
    "Don't you think it's a nice day?",
    'Phone number 5551234567 - call me.',
    'Computer, read the file; then speak.',
    'Knowledge, thought, through, though, rough, cough.',
    'Zero 0 7 19 20 21 99 101 1000 1984 2026 40000',
    'Yes you can see the yellow yacht.',
    'Character, church, judge, measure, ship, thing, which.',
]
for line in LINES:
    typed(m, line)
    want = ref(line)
    check(m.said == want, '%r\n        got  %s\n        want %s' % (line, names(m.said), names(want)) if m.said != want else repr(line))
# a long random-ish sentence of real words (one chunk: under 190 characters)
words = 'about after again air all also always america animal another answer any are around ask away back because before began being below between big book both boy but came can car change children city close come could country cut day did different does down each earth eat end enough even every example eye face family far father feet few find first follow food form found four friend from get girl give good got great group grow hand hard has have head hear help here high home house idea important just keep kind know land large last learn leave left let life light line list little live long look made make man many may mean men might mile miss more most mother mountain move much must name near need never new next night note now number often old once only open other our over own page paper part people picture place plant play point put question quick read real right river run said same saw say school sea second see sentence set she should show side since small some something song soon sound spell stand start state still stop story study such take talk tell than that their them then there these they thing think this those thought three through time together took tree try turn under until upon use very walk want watch water way well went were what when where while white who whole why will with without word work world would write year young'.split()
random.seed(7)
for t in range(6):
    line = ' '.join(random.sample(words, 22))[:118].rsplit(' ', 1)[0] + '.'
    typed(m, line, 80)
    want = ref(line)
    check(m.said == want, 'random %d (%d chars)%s' % (t, len(line), '' if m.said == want else '\n        ' + line + '\n        got  ' + names(m.said) + '\n        want ' + names(want)))
# /P shows the allophones
o = typed(m, '/P'); o = typed(m, 'Hello.')
check('HH1 EH LL OW' in o, '/P shows: %r' % o.strip()[-40:])
typed(m, '/P')
# /A by name and number
typed(m, '/A HH1 eh LL 53 xx')
check(m.said == [27, 7, 45, 53, 3], '/A: %s' % names(m.said))
# /F a file: several chunks, echoed
os.makedirs(os.path.join(HERE, 'test_disk'), exist_ok=True)
story = ('Once upon a time there was a little computer.\r\nIt could talk.\r\n\r\n'
         'Every day it read stories to the children, and they laughed. ' * 6)
open(os.path.join(HERE, 'test_disk', 'STORY.TXT'), 'w', newline='').write(story)
o = typed(m, '/F story.txt', 600)
check('Once upon a time' in o and 'It could talk.' in o, '/F echoes the text')
want = []
txt = story
# the 6502 splits into chunks at TB_MAX; compare the whole sequence without the PA4s between chunks
got = [a for a in m.said]
allw = ref(story)
def strip34(x): return [a for a in x if a not in (2, 3, 4)]
check(strip34(got) == strip34(allw), '/F story: the same sounds (%d allophones, %d SAY calls)' % (len(got), got.count(3)))
check(got.count(3) >= 3, 'in several chunks')
o = typed(m, '/F NOSUCH.TXT')
check("Can't read" in o, 'missing file: ' + o.strip()[-30:])
r = typed(m, '/Q')
check(m.stopped == 'menu', '/Q -> SBC_MENU (%r)' % m.stopped)
# no chip
m2 = machine(spo=False)
out = bytes(m2.out).decode('latin1')
check('No SPO256' in out, 'no chip: says so')
o = typed(m2, 'Hello.')
check('HH1 EH LL OW' in o and m2.said == [], 'no chip: shown, nothing spoken')
print('\n%d problems' % len(problems))
for p in problems: print('  ' + p.split('\n')[0])
