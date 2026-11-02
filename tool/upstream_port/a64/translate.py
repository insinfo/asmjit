import re, sys
src = open(sys.argv[1]).read().split('\n')
# Body: from the encoding switch to EmitDone (exclusive).
start = next(i for i,l in enumerate(src) if 'switch (inst_info->_encoding)' in l) + 1
end = next(i for i,l in enumerate(src) if l.strip() == 'EmitDone:')
body = src[start:end]

# Hoist labels nested inside blocks: the tail from the label to the end of
# its enclosing block becomes a top-level label at the end of the body and
# the label's place becomes `goto L;`.
continuations = {}

def hoist(body):
    depth = 1  # inside the switch
    in_switch = True
    out = []
    hoisted = []
    i = 0
    while i < len(body):
        l = body[i]
        code = re.sub(r'//.*', '', l)
        m = re.match(r'^([A-Za-z_]\w*):\s*$', l.strip())
        level = 1 if in_switch else 0
        if m and not l.strip().startswith(('case', 'default')) and depth > level:
            name = m.group(1)
            d = depth
            j = i + 1
            tail = []
            dd = d
            while j < len(body):
                c = re.sub(r'//.*', '', body[j])
                nd = dd + c.count('{') - c.count('}')
                if nd < d:
                    break
                tail.append(body[j])
                dd = nd
                j += 1
            last = [t for t in tail if t.strip() and not t.strip().startswith('//')]
            if not last or not last[-1].strip().startswith('goto'):
                sys.stderr.write(f'WARNING: hoisted {name} does not end with goto: {last[-1] if last else None}\n')
            out.append(' ' * (len(l) - len(l.lstrip()) + 2) + f'goto {name};')
            hoisted.append(f'{name}:')
            hoisted.extend(tail)
            # What follows the enclosing block in upstream.
            hoisted.extend(continuations.get(name, ['  goto InvalidInstruction;']))
            i = j
            continue
        depth += code.count('{') - code.count('}')
        if in_switch and depth == 0:
            # The closing brace of the encoding switch.
            in_switch = False
            depth = 0
            i += 1
            continue
        out.append(l)
        i += 1
    # The body falls through into EmitDone.
    return out + ['  goto EmitDone;'] + hoisted

# `case X: Label: {` on one line.
_split = []
for l in body:
    m = re.match(r'^(\s*case InstDB::kEncoding\w+:) (\w+): \{$', l)
    if m:
        _split.extend([m.group(1), m.group(2) + ':', '    {'])
    else:
        _split.append(l)
body = _split

# `case X: {` directly followed by a label: the label is an alias of the case.
_fixed = []
_k = 0
while _k < len(body):
    l = body[_k]
    if re.match(r'^\s*case InstDB::kEncoding\w+: \{$', l) and _k + 1 < len(body) and re.match(r'^[A-Za-z_]\w*:\s*$', body[_k+1].strip()):
        _fixed.append(l[:-2])
        _fixed.append(body[_k+1])
        _fixed.append('    {')
        _k += 2
        continue
    _fixed.append(l)
    _k += 1
body = hoist(_fixed)

def camel(n):
    parts = n.split('_')
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])

def state(n):
    return 'k' + n

OPT = {'None':0,'Reg':1,'Mem':2,'RegList':3,'Imm':4,'Label':5}
def encops(m):
    args = [a.strip() for a in m.group(2).split(',')]
    v = 0
    for i,a in enumerate(args): v += OPT[a] << (3*i)
    return f'{v} /* {m.group(0)} */'

def expr(l):
    l = l.replace('rm_rel->', 'rm_rel!.')
    l = l.replace('inst_info->', 'inst_info.')
    l = re.sub(r'op_ext\[EmitterUtils::kOp(\d)\]', r'opExt[\1]', l)
    l = re.sub(r'^(\s*)ASMJIT_ASSERT\((.*)\);', r'\1// ASMJIT_ASSERT(\2);', l)
    l = re.sub(r'ENC_OPS(\d)\(([^)]*)\)', encops, l)
    l = re.sub(r'\bconst InstDB::EncodingData::(\w+)& op_data = InstDB::EncodingData::(\w+)\[encoding_index\];', r'final op_data = \2[encodingIndex];', l)
    l = re.sub(r'\bInstDB::kEncoding(\w+)', r'A64Encoding.kEncoding\1', l)
    l = re.sub(r'\bInstDB::(k\w+)', r'\1', l)
    l = re.sub(r'\bInst::kId(\w+)', lambda m: f"_upIds['{m.group(1).lower()}']!", l)
    l = re.sub(r'\bRegType::k(\w+)', r'_RT.k\1', l)
    l = re.sub(r'\bVecElementType::k(\w+)', r'_ET.k\1', l)
    l = re.sub(r'\bShiftOp::k(\w+)', r'_ShiftOp.k\1', l)
    l = re.sub(r'\bCondCode::k(\w+)', r'_CC.k\1', l)
    l = re.sub(r'\bOffsetType::k(\w+)', r'A64OffsetType.k\1', l)
    l = re.sub(r'\bOffsetMode::k(\w+)', r'_kOffset\1', l)
    l = re.sub(r'\bGp::kId(\w+)', r'_kId\1', l)
    l = re.sub(r'\bInstOptions::k(\w+)', r'_IO.k\1', l)
    l = re.sub(r'\bOpcode::k(\w+)', r'Opcode.k\1', l)
    l = re.sub(r'\bSizeOp::k(\w+)', r'SizeOp.k\1', l)
    l = re.sub(r'\bVec::kSignatureElement(\w+)', lambda m: f'(_ET.k{m.group(1)} << 12)', l)
    l = re.sub(r'\bRegTraits<_RT\.k(\w+)>::kSignature', lambda m: f'_sigOf(_RT.k{m.group(1)})', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint64_t>\(\)', '.imm', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<int64_t>\(\)', '.imm', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint32_t>\(\)', '.immU32', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<int32_t>\(\)', '.immI32', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<double>\(\)', '.immAsDouble', l)
    l = re.sub(r'\.as<Imm>\(\)\.value\(\)', '.imm', l)
    l = re.sub(r'\.as<Imm>\(\)\.predicate\(\)', '.predicate', l)
    l = re.sub(r'\.as<Label>\(\)\.id\(\)', '.id', l)
    l = re.sub(r'\.as<(Reg|Mem|Gp|Vec|Imm|Label)>\(\)', '', l)
    l = re.sub(r'^(\s*)uint32_t (\w+) = (.*);(\s*//.*)?$', r'\1var \2 = _u32(\3);\4', l)
    l = re.sub(r'^(\s*)int32_t (\w+) = (.*);(\s*//.*)?$', r'\1var \2 = _i32(\3);\4', l)
    l = re.sub(r'\b(uint32_t|int32_t|uint64_t|int64_t|bool|size_t|uint8_t|InstId|intptr_t)\s+(\w+)\s*=', r'var \2 =', l)
    l = re.sub(r'^(\s*)uint32_t x;\s*$', r'\1// uint32_t x; (function-level)', l)
    l = re.sub(r'^(\s*)uint32_t (\w+);', r'\1int \2 = 0;', l)
    l = re.sub(r'^(\s*)LogicalImm (\w+);', r'\1final \2 = LogicalImm();', l)
    l = re.sub(r'^(\s*)LMHImm (\w+);', r'\1final \2 = LMHImm();', l)
    l = re.sub(r'^(\s*)SizeOp (\w+) =', r'\1var \2 =', l)
    l = re.sub(r'\bOut\((\w+)\)', r'\1', l)
    l = re.sub(r'\bcheck_gp_type\(([^;]*), &x\)', r'checkGpTypeX(\1)', l)
    l = re.sub(r'\bconst Operand_& (\w+) = ', r'final \1 = ', l)
    l = re.sub(r'\bconst (Imm|Mem|Gp|Reg|Vec)& (\w+) = ', r'final \2 = ', l)
    l = re.sub(r'\bstd::swap\((\w+), (\w+)\);', r'{ final t = \1; \1 = \2; \2 = t; }', l)
    l = l.replace('ASMJIT_UNLIKELY(', '(').replace('ASMJIT_LIKELY(', '(')
    l = re.sub(r'\bSupport::is_int_n<(\d+)>\(', r'_isIntN(\1, ', l)
    l = re.sub(r'\bSupport::is_uint_n<(\d+)>\(', r'_isUintN(\1, ', l)
    l = re.sub(r'\bSupport::lsb_mask<\w+>\(', '_lsbMask(', l)
    l = re.sub(r'\bSupport::bit_mask<\w+>\(', '_bitMask(', l)
    l = re.sub(r'\bSupport::min<\w+>\(', 'math.min(', l)
    l = re.sub(r'\bSupport::max<\w+>\(', 'math.max(', l)
    l = re.sub(r'\bSupport::is_power_of_2\(', '_isPowerOf2(', l)
    l = re.sub(r'\bSupport::(\w+)\(', lambda m: '_' + camel(m.group(1)) + '(', l)
    l = re.sub(r'\bUtils::(\w+)\(', lambda m: camel(m.group(1)) + '(', l)
    l = re.sub(r'\bEmitterUtils::(\w+)\(', lambda m: camel(m.group(1)) + '(', l)
    l = re.sub(r'\b(uint32_t|uint8_t|uint16_t|int32_t|FastUInt8)\(', lambda m: {'uint32_t':'_u32(','uint8_t':'_u8(','uint16_t':'_u16(','int32_t':'_i32(','FastUInt8':'('}[m.group(1)], l)
    l = re.sub(r'\b(uint64_t|int64_t|size_t|intptr_t)\(', '(', l)
    l = re.sub(r'(\d)u\b', r'\1', l)
    l = re.sub(r'(0x[0-9A-Fa-f]+)u\b', r'\1', l)
    l = re.sub(r'\b0b([01]+)\b', lambda m: hex(int(m.group(1),2)), l)
    l = re.sub(r'\bwriter\.(\w+)\(', lambda m: '_w.' + camel(m.group(1)) + '(', l)
    l = re.sub(r'\bopcode\.(\w+)\(', lambda m: 'opcode.' + camel(m.group(1)) + '(', l)
    l = re.sub(r'\boffset_format\.(\w+)\(', lambda m: 'offsetFormat.' + camel(m.group(1)) + '(', l)
    l = re.sub(r'\b(size_op|sz_op|sop|op)\.(\w+)\(', lambda m: m.group(1) + '.' + camel(m.group(2)) + '(', l)
    l = re.sub(r'\bop_data\.(\w+)\(\)', r'op_data.\1', l)
    l = re.sub(r'^(\s*)opcode = (.*);', r'\1opcode.reset(\2);', l)
    l = re.sub(r'\bopcode (\|=|\^=|&=) ', r'opcode.v \1 ', l)
    l = re.sub(r'\(opcode ([&|^]) ', r'(opcode.v \1 ', l)
    l = re.sub(r'\b([a-z_]+)\.reg_type\(\)', r'\1.regType', l)
    l = re.sub(r'\b([a-z_]+)\.element_type\(\)', r'\1.elementType', l)
    l = re.sub(r'\b([a-z_]+)\.element_index\(\)', r'\1.elementIndex', l)
    # Operand accessors.
    l = re.sub(r'\b(o\d|rm_rel!|m|mem|o3|o4|o5|vec|reg)\.([a-z_0-9]+)\(\)', lambda m: f'{m.group(1)}.{camel(m.group(2))}' + ('()' if m.group(2).startswith(('is_','has_')) else ''), l)
    l = re.sub(r'\b(o\d|rm_rel!|m|mem)\.([a-z_0-9]+)\(', lambda m: f'{m.group(1)}.{camel(m.group(2))}(', l)
    l = re.sub(r'\b(rm_rel|inst_id|inst_info|inst_flags|inst_cc|encoding_index|offset_format|offset_value|multiple_op_data|multiple_op_count|is_rex_invalid)\b', lambda m: camel(m.group(1)), l)
    l = re.sub(r'(?<![.\w])([a-z]+(?:_[a-z0-9]+)+)\(', lambda m: camel(m.group(1)) + '(', l)
    l = re.sub(r'&opcode\b', 'opcode', l)
    l = re.sub(r'&sz\b', 'szOut', l)
    l = re.sub(r'\bdiff\(', '_diff(', l)
    l = re.sub(r'\.(reg_type|element_type|element_index)\(\)', lambda m: '.' + camel(m.group(1)), l)
    l = re.sub(r'\.((?:is|has)_\w+)\(', lambda m: '.' + camel(m.group(1)) + '(', l)
    l = re.sub(r'\.(isVec\w*|isGp\w*|hasElement\w*)\(\)', lambda m: '.' + m.group(1) + '()', l)
    l = re.sub(r'\bstatic const (?:uint32_t|uint8_t|uint16_t) (\w+)\[\d*\] = \{ (.*) \};', r'final \1 = [\2];', l)
    l = re.sub(r'\bstatic const (?:uint32_t|uint8_t|uint16_t) (\w+)\[\d*\] = \{\s*$', r'final \1 = [', l)
    l = re.sub(r'\bstatic constexpr (?:uint32_t|uint8_t) (\w+)\[\d*\] = \{ (.*) \};', r'final \1 = [\2];', l)
    l = re.sub(r'instInfo = &InstDB::_inst_info_table\[instId\];', 'instInfo = kA64UpInstInfo[instId];', l)
    l = l.replace('instInfo._encoding_data_index', 'instInfo.encodingDataIndex')
    l = re.sub(r'\((instFlags & \w+)\) \?', r'(\1) != 0 ?', l)
    l = re.sub(r'(op_data\.\w+) \?', r'\1 != 0 ?', l)
    l = re.sub(r'\bif \((\w+) && !(\w+)\)', r'if (\1 != 0 && \2 == 0)', l)
    l = re.sub(r'else if \((\w+)\) \{', r'else if (\1 != 0) {', l)
    l = re.sub(r'\((\w+) / (\d+)\)', r'(\1 ~/ \2)', l)
    l = re.sub(r'\.(regType|elementType|elementIndex)\(\)', r'.\1', l)
    l = re.sub(r'op_data\.(has_register_op|has_zero_op) != 0', r'op_data.\1', l)
    l = re.sub(r'= (opcode\.get\(\) & _B\(\d+\)) \?', r'= (\1) != 0 ?', l)
    l = re.sub(r'\bif \(!\((opcode\.get\(\)|imm) & _B\((\d+)\)\)\)', r'if ((\1 & _B(\2)) == 0)', l)
    l = re.sub(r'\bif \((op_data\.\w+) & \((1 << \d+)\)\)', r'if ((\1 & (\2)) != 0)', l)
    l = re.sub(r'\bif \((q_is_optional|inverted)\)', r'if (\1 != 0)', l)
    l = re.sub(r'!(size_op\.q\(\))', r'\1 == 0', l)
    l = re.sub(r'\bshift /= 8;', 'shift ~/= 8;', l)
    l = re.sub(r'\bif \((s) && ', r'if (\1 != 0 && ', l)
    l = re.sub(r'\bif \(!x \|\| ', 'if (x == 0 || ', l)
    l = re.sub(r'&& x\)', '&& x != 0)', l)
    l = re.sub(r'&& !x\)', '&& x == 0)', l)
    # uint64_t values: logical shifts and unsigned comparisons.
    l = re.sub(r'\b(imm64|imm|value|imm_value) >> 32\b', r'\1 >>> 32', l)
    l = re.sub(r'\bif \(imm64 > 0xFFFFFFFF\)', 'if (imm64 < 0 || imm64 > 0xFFFFFFFF)', l)
    # uint32_t shifts wrap at 32 bits.
    l = re.sub(r'\b_u32\((\w+)\) << (\w+) != ', r'_u32(_u32(\1) << \2) != ', l)
    # Integer conditions (C++ ints used as booleans).
    l = re.sub(r'\bx \? ', 'x != 0 ? ', l)
    l = re.sub(r'\bif \(!x\)', 'if (x == 0)', l)
    l = re.sub(r'\(!x && ', '(x == 0 && ', l)
    l = re.sub(r'rmRel = &(\w+);', r'rmRel = \1;', l)
    l = re.sub(r'!op_data\.(\w+)\b(?!\s*[=!<>]=)', r'(op_data.\1 == 0)', l)
    l = re.sub(r'(if \(|&& |\|\| )op_data\.(\w+)(?=\s*(&&|\|\||\)))', r'\1op_data.\2 != 0', l)
    l = re.sub(r'\bif \(!\(([\w.()]+) & ([^()]+|\([^()]*\))\)\)', r'if ((\1 & \2) == 0)', l)
    l = re.sub(r'\bif \((?!\()([\w.()]+) & ([\w.]+(?:\([^()]*\))?)\)', r'if ((\1 & \2) != 0)', l)
    l = re.sub(r'= (opcode\.get\(\) & _B\(\d+\)) \?', r'= (\1) != 0 ?', l)
    l = re.sub(r'\bif \((\w+) \|\| ', r'if (\1 != 0 || ', l)
    l = re.sub(r'\b(imm\w*)\.value_as<u?int64_t>\(\)', r'\1.imm', l)
    l = re.sub(r'\b(imm\w*)\.value_as<uint32_t>\(\)', r'\1.immU32', l)
    l = re.sub(r'\b(imm\w*)\.value\(\)', r'\1.imm', l)
    l = re.sub(r'\bshift_op_to_ld_st_opt_map\[([^\]]*)\]', r'shiftOpToLdStOptMap(\1)', l)
    l = re.sub(r'\bB\(', '_B(', l)
    return l

out = []
labels = []
def is_term(line):
    t = line.strip()
    return t.startswith('{ s = ') or t.startswith('goto ') or t == 'break;' or t.startswith('throw ') or t.startswith('return')

lines = []
for l in body:
    if re.match(r'^\s*//', l) or not l.strip():
        lines.append(('c', l)); continue
    m = re.match(r'^\s*case InstDB::kEncoding(\w+):\s*(\{)?\s*$', l)
    if m:
        lines.append(('case', 'enc' + m.group(1), bool(m.group(2)))); continue
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s*$', l.strip()) if not l.strip().startswith('default') else None
    if m and not l.strip().startswith('case'):
        lines.append(('label', m.group(1), False)); continue
    lines.append(('s', l))

# Resolve fallthrough targets.
def next_label(i):
    for j in range(i+1, len(lines)):
        if lines[j][0] in ('case','label'): return lines[j][1]
    return None

states = []
in_array = False
inner_switch = []
brace_depth = 0
prev_code = None
result = []
for i, item in enumerate(lines):
    kind = item[0]
    if kind in ('case', 'label'):
        name = item[1]
        states.append(name)
        if prev_code is not None and not is_term(prev_code) and prev_code.strip() not in ('}', '{'):
            result.append(f'        s = _S.{name}; continue loop;')
        elif prev_code is not None and prev_code.strip() == '}':
            # A closing brace of a case block `case X: { ... }`: if the block didn't end with a terminator
            # the analyzer will tell; add the transition anyway (dead code otherwise).
            result.append(f'        s = _S.{name}; continue loop; // (after block)')
        result.append(f'      case _S.{name}:' + (' {' if item[2] else ''))
        prev_code = None
        continue
    if kind == 'c':
        result.append(item[1]); continue
    l = item[1]
    t = l.strip()
    # Inner switches: their `break` and `default` stay.
    code_t = re.sub(r'//.*', '', l)
    if re.search(r'\bswitch \(', code_t):
        inner_switch.append(brace_depth)
    brace_depth += code_t.count('{') - code_t.count('}')
    if inner_switch and brace_depth <= inner_switch[-1]:
        inner_switch.pop()
    if not inner_switch and t in ('default:',):
        result.append('      // (upstream main switch default)')
        continue
    if t == '[[fallthrough]];':
        nl = next_label(i)
        l = l.replace('[[fallthrough]];', f'{{ s = _S.{nl}; continue loop; }}')
    elif t == 'break;' and not inner_switch:
        l = l.replace('break;', '{ s = _S.InvalidInstruction; continue loop; }')
    else:
        l = re.sub(r'\bgoto (\w+);', lambda m: f'{{ s = _S.{m.group(1)}; continue loop; }}', l)
    l = expr(l)
    if in_array and l.strip() == '};':
        l = l.replace('};', '];')
        in_array = False
    if l.rstrip().endswith('= ['):
        in_array = True
    result.append(l)
    prev_code = l

open(sys.argv[2], 'w').write('\n'.join(result))
open(sys.argv[3], 'w').write('\n'.join(states))
print(len(result), 'lines', len(states), 'states')
