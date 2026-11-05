# usage (from the smb folder):  python3 test/runf.py OUTDIR scene ...   (or "all", or "new")
"""Runs some of the set-piece scenes of features.py and newfeat.py (each scene is a
"# ---- " section) so the tests can be split over several processes."""
import sys, os, re
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'features.py')).read()
head, rest = src.split('\n# ---- a ? block', 1)
rest = '# ---- a ? block' + rest
body, foot = rest.split('\nbad = [r', 1)
body += '\n' + open(os.path.join(here, 'newfeat.py')).read()
chunks = re.split(r'\n(?=# ---- )', body)
want = sys.argv[2:]
def names(c): return re.findall(r"Scene\('(\w+)'", c)
pick = [c for c in chunks if 'all' in want or set(names(c)) & set(want) or ('new' in want and 'NEW' in c[:200])]
print('scenes:', ' '.join(n for c in pick for n in names(c)))
sys.argv = sys.argv[:2]
code = head + '\n' + '\n'.join(pick) + '\nbad = [r' + foot
exec(compile(code, os.path.join(here, 'features.py'), 'exec'))
