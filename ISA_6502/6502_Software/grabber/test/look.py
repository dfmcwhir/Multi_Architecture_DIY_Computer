# PY65=... python3 test/look.py OUTDIR: screenshots of the title, a level, the shop
from gtest import *
OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
g = Game(); mc = g.mc
mc.run(3_000_000); mc.term.png(OUT + '/title.png')
mc.set_pad(0x08); mc.run(50_000); mc.set_pad(0)
mc.run(3_000_000); mc.term.png(OUT + '/level_intro.png')
mc.run(6_000_000); mc.term.png(OUT + '/level.png')
print(g.text()[:400])
for k in range(20):
    mc.set_pad(0x01 if k == 0 else 0); mc.run(200_000)
mc.term.png(OUT + '/out.png')
print('hst', g.v('hst'), 'hook', g.v('hx'), g.v('hy'), 'carry', g.v('carry'), 'money', g.n3('money'), 'errors', mc.term.errors[:3])
