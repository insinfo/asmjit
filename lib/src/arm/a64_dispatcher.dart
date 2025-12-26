import '../core/labels.dart';
import 'a64.dart';
import 'a64_assembler.dart';
import 'a64_inst_db.g.dart';

/// Dispatches A64 instruction IDs to assembler methods for the supported set.
/// Unhandled IDs are no-ops, matching the x86 dispatcher behavior.
void a64Dispatch(A64Assembler asm, int instId, List<Object> ops) {
  switch (instId) {
    case A64InstId.kAdd:
      _add(asm, ops);
      break;
    case A64InstId.kSub:
      _sub(asm, ops);
      break;
    case A64InstId.kAnd:
      _binaryReg(asm, ops, (rd, rn, rm) => asm.and(rd, rn, rm));
      break;
    case A64InstId.kOrr:
      _binaryReg(asm, ops, (rd, rn, rm) => asm.orr(rd, rn, rm));
      break;
    case A64InstId.kEor:
      _binaryReg(asm, ops, (rd, rn, rm) => asm.eor(rd, rn, rm));
      break;
    case A64InstId.kAdds:
      _adds(asm, ops);
      break;
    case A64InstId.kSubs:
      _subs(asm, ops);
      break;
    case A64InstId.kCmp:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
        asm.cmp(ops[0] as A64Gp, ops[1] as A64Gp);
      } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
        asm.cmpImm(ops[0] as A64Gp, ops[1] as int);
      }
      break;
    case A64InstId.kCmn:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
        asm.cmnImm(ops[0] as A64Gp, ops[1] as int);
      }
      break;
    case A64InstId.kMov:
    case A64InstId.kMovn:
    case A64InstId.kMovz:
      _mov(asm, ops);
      break;
    case A64InstId.kB:
      _b(asm, ops);
      break;
    case A64InstId.kBl:
      _bl(asm, ops);
      break;
    case A64InstId.kCbz:
      _cb(asm, ops, zero: true);
      break;
    case A64InstId.kCbnz:
      _cb(asm, ops, zero: false);
      break;
    case A64InstId.kB_cond:
      _bCond(asm, ops);
      break;
    case A64InstId.kLdr:
      _ldr(asm, ops);
      break;
    case A64InstId.kStr:
      _str(asm, ops);
      break;
    default:
      break;
  }
}

void _add(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.add(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _sub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.sub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _adds(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _subs(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _binaryReg(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Gp) fn) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  }
}

void _mov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.movImm64(ops[0] as A64Gp, ops[1] as int);
  }
}

void _b(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.b(ops[0] as Label);
  }
}

void _bl(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.bl(ops[0] as Label);
  }
}

void _bCond(A64Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final cond = ops[0];
  final label = ops[1];
  if (cond is A64Cond && label is Label) {
    asm.bCond(cond, label);
  }
}

void _cb(A64Assembler asm, List<Object> ops, {required bool zero}) {
  if (ops.length != 2) return;
  final rt = ops[0];
  final lbl = ops[1];
  if (rt is A64Gp && lbl is Label) {
    if (zero) {
      asm.cbz(rt, lbl);
    } else {
      asm.cbnz(rt, lbl);
    }
  }
}

void _ldr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldr(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _str(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.str(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
