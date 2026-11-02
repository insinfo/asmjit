
import re
S='/private/tmp/claude-501/-Volumes-ssd-dock-MyProjectsDart-asmjit/ac579a70-6b8a-4971-9dad-c3d5e7d3806b/scratchpad/x86port/'
head=open(S+'head.dart.txt').read()
body=open(S+'body.dart.txt').read()
for patch in sorted(__import__('glob').glob(S+'patch_*.py')):
    exec(open(patch).read())
states=open(S+'states.txt').read().split('\n')
errors=['InvalidInstruction','AmbiguousOperandSize','InvalidAddress','OperandSizeMismatch','Failed','InvalidRexPrefix','InvalidEROrSAE','InvalidDisplacement','OutOfMemory','InvalidSegment','InvalidRepPrefix','InvalidLabel','InvalidImmediate','InvalidBroadcast','InvalidXReleasePrefix','InvalidXAcquirePrefix','InvalidPhysId','InvalidLockPrefix','InvalidAddressIndex','InvalidAddress64Bit']
allstates=states+['EmitDone']+errors
enc_src=open('lib/src/asmjit/x86/x86_opcode.dart').read()
encnames=re.findall(r"^    '(\w+)',$", enc_src[enc_src.index('static const names'):], re.M)
encmap=",\n".join(f"  _S.enc{n}" if ('enc'+n) in states else f"  _S.InvalidInstruction /* {n} */" for n in encnames)
footer="""
      case _S.EmitDone:
        return;

"""+"".join(f"      case _S.{e}:\n        _fail('{e}', instId, opArray);\n" for e in errors)+"""      }
    }
  }

  Never _fail(String error, int instId, List<_Op> ops) {
    final name = instId > 0 && instId < kX86InstDb.length
        ? kX86InstDb[instId].name
        : '#$instId';
    throw X86EmitError(error, name);
  }
}

/// An instruction the encoder cannot encode (upstream error name).
class X86EmitError extends ArgumentError {
  final String error;
  final String instruction;
  X86EmitError(this.error, this.instruction) : super('x86 $instruction: $error');
}

/// States of [X86Emitter._emit]: the cases and labels of upstream `_emit()`.
enum _S {
"""+",\n".join(f"  {st}" for st in allstates)+""",
}

/// Entry state of each [X86Encoding].
const _encodingStates = [
"""+encmap+""",
];
"""
open('lib/src/asmjit/x86/x86_emit.dart','w').write(head+body+footer)
