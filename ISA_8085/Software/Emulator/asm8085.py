#!/usr/bin/env python3
"""Minimal 8080/8085 assembler (subset of Macroassembler AS syntax) used only to test the ROM."""
import re, sys, os

REGS = {'B':0,'C':1,'D':2,'E':3,'H':4,'L':5,'M':6,'A':7}
RP   = {'B':0,'D':1,'H':2,'SP':3}
RPP  = {'B':0,'D':1,'H':2,'PSW':3}
NOARG = {'NOP':0x00,'RLC':0x07,'RRC':0x0F,'RAL':0x17,'RAR':0x1F,'DAA':0x27,'CMA':0x2F,'STC':0x37,'CMC':0x3F,
 'HLT':0x76,'RET':0xC9,'XCHG':0xEB,'XTHL':0xE3,'SPHL':0xF9,'PCHL':0xE9,'EI':0xFB,'DI':0xF3,'RIM':0x20,'SIM':0x30,
 'RNZ':0xC0,'RZ':0xC8,'RNC':0xD0,'RC':0xD8,'RPO':0xE0,'RPE':0xE8,'RP':0xF0,'RM':0xF8}
ALU = {'ADD':0x80,'ADC':0x88,'SUB':0x90,'SBB':0x98,'ANA':0xA0,'XRA':0xA8,'ORA':0xB0,'CMP':0xB8}
IMM = {'ADI':0xC6,'ACI':0xCE,'SUI':0xD6,'SBI':0xDE,'ANI':0xE6,'XRI':0xEE,'ORI':0xF6,'CPI':0xFE,'IN':0xDB,'OUT':0xD3}
ADDR = {'JMP':0xC3,'JNZ':0xC2,'JZ':0xCA,'JNC':0xD2,'JC':0xDA,'JPO':0xE2,'JPE':0xEA,'JP':0xF2,'JM':0xFA,
 'CALL':0xCD,'CNZ':0xC4,'CZ':0xCC,'CNC':0xD4,'CC':0xDC,'CPO':0xE4,'CPE':0xEC,'CP':0xF4,'CM':0xFC,
 'LDA':0x3A,'STA':0x32,'LHLD':0x2A,'SHLD':0x22}

class AsmError(Exception): pass

def strip_comment(line):
    q=None
    for i,ch in enumerate(line):
        if q:
            if ch==q: q=None
        elif ch in '\'"': q=ch
        elif ch==';': return line[:i]
    return line

def split_ops(s):
    out=[];cur='';q=None
    for ch in s:
        if q:
            cur+=ch
            if ch==q: q=None
        elif ch in '\'"': q=ch; cur+=ch
        elif ch==',': out.append(cur.strip()); cur=''
        else: cur+=ch
    if cur.strip() or out: out.append(cur.strip())
    return out

TOK = re.compile(r"""\s*(?:
 (?P<chr>'(?:[^'])'|"(?:[^"])")|
 (?P<hex>[0-9][0-9A-Fa-f]*[Hh](?![A-Za-z0-9_]))|
 (?P<hex2>\$[0-9A-Fa-f]+)|
 (?P<dec>[0-9]+)|
 (?P<sym>[A-Za-z_.][A-Za-z0-9_.]*)|
 (?P<pc>\$)|
 (?P<op><<|>>|[-+*/%&|^~()])
)""", re.X)

class Asm:
    def __init__(self):
        self.syms={}; self.mem=bytearray(65536); self.used=[False]*65536
        self.pc=0; self.pass_no=1; self.errors=[]
    def ev(self, s, line=''):
        s=s.strip(); pos=0; out=[]
        while pos<len(s):
            m=TOK.match(s,pos)
            if not m or m.end()==pos: raise AsmError("bad expr %r in %r"%(s,line))
            pos=m.end(); k=m.lastgroup; t=m.group(k)
            if k=='chr': out.append(str(ord(t[1])))
            elif k=='hex': out.append(str(int(t[:-1],16)))
            elif k=='hex2': out.append(str(int(t[1:],16)))
            elif k=='dec': out.append(str(int(t)))
            elif k=='pc': out.append(str(self.pc))
            elif k=='sym':
                u=t.upper()
                if u in self.syms: out.append(str(self.syms[u]))
                elif self.pass_no==1: out.append('0')
                else: raise AsmError("undefined symbol %s in %r"%(t,line))
            else: out.append({'/':'//'}.get(t,t))
        try: return int(eval(' '.join(out),{}))
        except Exception as e: raise AsmError("eval fail %r: %s"%(s,e))
    def emit(self,*bs):
        for b in bs:
            if self.pass_no==2:
                if self.used[self.pc] and False: pass
                self.mem[self.pc]=b&0xFF; self.used[self.pc]=True
            self.pc+=1
    def reg(self,s):
        s=s.strip().upper()
        if s not in REGS: raise AsmError("bad reg "+s)
        return REGS[s]
    def assemble_file(self,path):
        self.dirs=[os.path.dirname(os.path.abspath(path))]
        lines=self.read(path)
        for p in (1,2):
            self.pass_no=p; self.pc=0
            for (fn,ln,text) in lines:
                try:
                    if self.line(text) == 'END': break
                except AsmError as e:
                    raise AsmError("%s:%d: %s"%(fn,ln,e))
    def read(self,path):
        out=[]
        for i,l in enumerate(open(path).read().split('\n')):
            t=strip_comment(l).rstrip()
            m=re.match(r'\s*include\s+"([^"]+)"',t,re.I)
            if m:
                out+=self.read(os.path.join(os.path.dirname(os.path.abspath(path)),m.group(1)))
            else: out.append((os.path.basename(path),i+1,t))
        return out
    def line(self,t):
        if not t.strip(): return
        label=None
        if not t[0].isspace():
            m=re.match(r'([A-Za-z_.][A-Za-z0-9_.]*):?\s*(.*)$',t)
            label,rest=m.group(1),m.group(2)
        else:
            m=re.match(r'\s*([A-Za-z_.][A-Za-z0-9_.]*):\s*(.*)$',t)
            if m: label,rest=m.group(1),m.group(2)
            else: rest=t.strip()
        rest=rest.strip()
        parts=rest.split(None,1)
        op=parts[0].upper() if parts else ''
        arg=parts[1].strip() if len(parts)>1 else ''
        if op=='EQU':
            self.syms[label.upper()]=self.ev(arg,t); return
        if label:
            u=label.upper()
            if self.pass_no==1 and u in self.syms and self.syms[u]!=self.pc: raise AsmError("dup label "+label)
            self.syms[u]=self.pc
        if not op: return
        return self.inst(op,arg,t)
    def inst(self,op,arg,t):
        a=split_ops(arg)
        if op=='CPU' or op=='END' and False: return
        if op=='END': return 'END'
        if op=='ORG': self.pc=self.ev(arg,t); return
        if op=='DB':
            for x in a:
                if len(x)>=3 and x[0] in '\'"' and x[-1]==x[0] and len(x)>3:
                    for ch in x[1:-1]: self.emit(ord(ch))
                else: self.emit(self.ev(x,t))
            return
        if op=='DW':
            for x in a:
                v=self.ev(x,t); self.emit(v&255,(v>>8)&255)
            return
        if op=='DS': self.pc+=self.ev(arg,t); return
        if op in NOARG: self.emit(NOARG[op]); return
        if op=='MOV': self.emit(0x40|self.reg(a[0])<<3|self.reg(a[1])); return
        if op=='MVI': self.emit(0x06|self.reg(a[0])<<3,self.ev(a[1],t)); return
        if op=='LXI':
            v=self.ev(a[1],t); self.emit(0x01|RP[a[0].upper()]<<4,v&255,(v>>8)&255); return
        if op in ('LDAX','STAX'):
            self.emit({'LDAX':0x0A,'STAX':0x02}[op]|RP[a[0].upper()]<<4); return
        if op in ALU: self.emit(ALU[op]|self.reg(a[0])); return
        if op in IMM: self.emit(IMM[op],self.ev(a[0],t)); return
        if op=='INR': self.emit(0x04|self.reg(a[0])<<3); return
        if op=='DCR': self.emit(0x05|self.reg(a[0])<<3); return
        if op in ('INX','DCX','DAD'):
            self.emit({'INX':0x03,'DCX':0x0B,'DAD':0x09}[op]|RP[a[0].upper()]<<4); return
        if op in ('PUSH','POP'):
            self.emit({'PUSH':0xC5,'POP':0xC1}[op]|RPP[a[0].upper()]<<4); return
        if op in ADDR:
            v=self.ev(a[0],t); self.emit(ADDR[op],v&255,(v>>8)&255); return
        if op=='RST': self.emit(0xC7|self.ev(a[0],t)<<3); return
        if op=='CPU': return
        raise AsmError("unknown op %s"%op)

if __name__=='__main__':
    A=Asm(); A.assemble_file(sys.argv[1])
    hi=max(i for i,u in enumerate(A.used) if u)
    open(sys.argv[2],'wb').write(bytes(A.mem[:hi+1]))
    print("assembled %d bytes, last address %04X"%(sum(A.used),hi))
