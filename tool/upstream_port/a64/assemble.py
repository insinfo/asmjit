import re, glob
S='/private/tmp/claude-501/-Volumes-ssd-dock-MyProjectsDart-asmjit/ac579a70-6b8a-4971-9dad-c3d5e7d3806b/scratchpad/a64port/'
head=open(S+'head.dart.txt').read()
body=open(S+'body.dart.txt').read()
def _rep(old, new, count=1):
    global body
    if body.count(old) != count:
        raise SystemExit(f'patch: expected {count} of:\n{old[:300]}\nfound {body.count(old)}')
    body = body.replace(old, new)
def _span(start, end, new):
    global body
    i = body.index(start); j = body.index(end, i) + len(end)
    body = body[:i] + new + body[j:]
body = re.sub(r'\bs = _S\.', 'state = _S.', body)
for patch in sorted(glob.glob(S+'patch_*.py')):
    exec(open(patch).read())
states=open(S+'states.txt').read().split('\n')
errors=['OutOfMemory','InvalidAddress','InvalidAddressScale','InvalidDisplacement','InvalidElementIndex','InvalidLabel','InvalidImmediate','InvalidInstruction','InvalidPhysId','InvalidRegType','Failed']
allstates=states+['EmitDone']+errors
src=open('/Volumes/ssd_dock/MyProjectsDart/asmjit/lib/src/asmjit/arm/a64_instdb.dart').read()
encnames=re.findall(r"^    '(\w+)',$", src[src.index('static const names'):], re.M)
encmap=",\n".join(f"  _S.enc{n}" if ('enc'+n) in states else f"  _S.InvalidInstruction /* {n} */" for n in encnames)
footer="""
      case _S.EmitDone:
        return;

"""+"".join(f"      case _S.{e}:\n        _fail('{e}', instId);\n" for e in errors)+"""      }
    }
  }

  Never _fail(String error, int instId) {
    final name = instId > 0 && instId < kA64UpInstNames.length
        ? kA64UpInstNames[instId]
        : '#$instId';
    throw A64EmitError(error, name);
  }
}

/// An instruction the encoder cannot encode (upstream error name).
class A64EmitError extends ArgumentError {
  final String error;
  final String instruction;
  A64EmitError(this.error, this.instruction) : super('a64 $instruction: $error');
}

/// States of [A64Emitter._emit]: the cases and labels of upstream `_emit()`.
enum _S {
"""+",\n".join(f"  {st}" for st in allstates)+""",
}

/// Entry state of each [A64Encoding].
const _encodingStates = [
"""+encmap+""",
];
"""
open('/Volumes/ssd_dock/MyProjectsDart/asmjit/lib/src/asmjit/arm/a64_emit.dart','w').write(head+body+footer)
