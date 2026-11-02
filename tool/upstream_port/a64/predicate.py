import re
R='/Volumes/ssd_dock/MyProjectsDart/asmjit/referencias/asmjit-master/asmjit/arm/a64globals.h'
src=open(R).read()
b=src.index('namespace Predicate {'); e=src.index('} // {Predicate}')
body=src[b:e]
def cnum(t):
    t=t.strip().rstrip('u').rstrip('U')
    if t.startswith('0b'): return int(t[2:],2)
    return int(t,0)
out=[]
byname=[]
for m in re.finditer(r'\nnamespace (\w+) \{(.*?)\n\}', body, re.S):
    ns, nb = m.group(1), m.group(2)
    enc = re.search(r'encode\(([^)]*)\) noexcept \{\s*return (.*?);', nb, re.S)
    params=[]; fexpr=None
    if enc:
        params=[p.split()[-1] for p in enc.group(1).split(',')]
        fexpr=enc.group(2)
    doc=re.search(r'//! (.*)\n', nb)
    cls='A64'+ns
    lines=[f'/// `a64::Predicate::{ns}`' + (f': {doc.group(1).rstrip(".")}.' if doc else '.'), f'abstract final class {cls} {{']
    if enc:
        dparams=', '.join(f'int {p}' for p in params)
        dexpr=fexpr.replace('\n',' ')
        dexpr=re.sub(r'\s+',' ',dexpr)
        lines.append(f'  /// `encode()`.')
        lines.append(f'  static int encode({dparams}) => {dexpr};')
        lines.append('')
    for em in re.finditer(r'^\s*(k\w+)\s*=\s*(encode\([^)]*\)|[^,\n]+?)\s*,?\s*(//.*)?$', nb, re.M):
        name, val = em.group(1), em.group(2).strip()
        cm=re.match(r'encode\((.*)\)$', val)
        if cm:
            args=[cnum(a) for a in cm.group(1).split(',')]
            env=dict(zip(params,args))
            v=eval(re.sub(r'\b(\w+)\b', lambda x: str(env[x.group(1)]) if x.group(1) in env else x.group(1), fexpr.replace('u','')))
        else:
            v=cnum(val)
        lines.append(f'  static const int {name} = 0x{v:X};')
        byname.append(f"  '{ns}::{name}': {cls}.{name},")
    lines.append('}')
    out.append('\n'.join(lines))
hdr='''// Port of the `a64::Predicate` namespace (asmjit/arm/a64globals.h):
// immediates of AT, BTI, DMB/DSB, DC, IC, ISB, PRFM, PSB, TLBI, TSB, MSR
// (PState) and MRS/MSR system registers. Generated once from upstream by a
// script that evaluates the `encode()` values; names keep upstream spelling.

// ignore_for_file: constant_identifier_names

'''
tail='\n\n/// Every predicate by upstream name (`PRFOp::kPLDL1KEEP`).\nconst kA64Predicates = <String, int>{\n'+'\n'.join(byname)+'\n};\n'
open('/Volumes/ssd_dock/MyProjectsDart/asmjit/lib/src/asmjit/arm/a64_predicate.dart','w').write(hdr+'\n\n'.join(out)+tail)
print(len(out), 'namespaces')
