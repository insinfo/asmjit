import re, sys
src = open(sys.argv[1]).read().split('\n')
# Body: from the encoding switch to EmitDone (exclusive).
start = next(i for i,l in enumerate(src) if 'switch (inst_info->_encoding)' in l) + 1
end = next(i for i,l in enumerate(src) if l.strip() == 'EmitDone:')
body = src[start:end]

# Hoist labels nested inside blocks: the tail from the label to the end of
# its enclosing block becomes a top-level label at the end of the body and
# the label's place becomes `goto L;`.
continuations = {
    # EmitModVSib is in the `else if` of EmitModSib's address chain, which is
    # followed by the immediate.
    'EmitModVSib': ['  writer.emit_immediate(uint64_t(imm_value), imm_size);', '  goto EmitDone;'],
}

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

body = hoist(body)

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
    l = re.sub(r'^(\s*)ASMJIT_ASSERT\((.*)\);', r'\1// ASMJIT_ASSERT(\2);', l)
    l = re.sub(r'\b(static )?constexpr (uint32_t|int32_t|uint64_t) ', 'const ', l)
    l = re.sub(r'op_ext\[EmitterUtils::kOp(\d)\]', r'opExt[\1]', l)
    l = re.sub(r'FIXUP_GPB\((\w+), (\w+)\);', lambda m: f'{camel(m.group(2))} = fixupGpb({m.group(1)}, {camel(m.group(2))});', l)
    l = l.replace('rm_rel->', 'rm_rel!.')
    l = l.replace('common_info->', 'common_info.')
    l = l.replace('inst_info->', 'inst_info.')
    l = re.sub(r'ENC_OPS(\d)\(([^)]*)\)', encops, l)
    l = re.sub(r'\bInstDB::kEncoding(\w+)', r'X86Encoding.kEncoding\1', l)
    l = re.sub(r'\bInstDB::InstFlags::k(\w+)', r'X86InstDbFlags.k\1', l)
    l = re.sub(r'\bOpcode::k(\w+)', r'X86Opcode.k\1', l)
    l = re.sub(r'\bInstOptions::k(\w+)', r'_IO.k\1', l)
    l = re.sub(r'\bGp::kId(\w+)', r'_kId\1', l)
    l = re.sub(r'\bSReg::kId(\w+)', r'_kSeg\1', l)
    l = re.sub(r'\bRegType::k(\w+)', r'_RT.k\1', l)
    l = re.sub(r'\bInst::kId(\w+)', r'X86InstId.k\1', l)
    l = re.sub(r'\bMem::AddrType::k(\w+)', r'_Addr.k\1', l)
    l = re.sub(r'\bEncodingOptions::k(\w+)', r'EncodingOptions.k\1', l)
    l = re.sub(r'\bkX86MemInfo_(\w+)', r'_kMemInfo\1', l)
    l = re.sub(r'\bkX86Byte(\w+)', r'_kByte\1', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint8_t>\(\)', r'.immU8', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint16_t>\(\)', r'.immU16', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint32_t>\(\)', r'.immU32', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<uint64_t>\(\)', r'.imm', l)
    l = re.sub(r'\.as<Imm>\(\)\.value_as<int64_t>\(\)', r'.imm', l)
    l = re.sub(r'\.as<Imm>\(\)\.value\(\)', r'.imm', l)
    l = re.sub(r'\.as<Label>\(\)\.id\(\)', r'.labelId', l)
    l = re.sub(r'\.as<(Reg|Mem|Gp|Vec|Imm)>\(\)', '', l)
    l = l.replace('rm_rel->', 'rm_rel!.')
    l = l.replace('common_info->', 'common_info.')
    l = l.replace('inst_info->', 'inst_info.')
    # opcode helpers (statement level).
    l = re.sub(r'\bopcode\.(add_prefix_by_size|add_arith_by_size|add_w_by_size|add_66h_by_size|add_w_if|add_66h_if|force_evex_if|add)\((.*)\);', lambda m: f'opcode = _{camel(m.group(1))}(opcode, {m.group(2)});', l)
    l = re.sub(r'\bopcode\.(add_w|add_66h|force_evex)\(\);', lambda m: f'opcode = _{camel(m.group(1))}(opcode);', l)
    l = re.sub(r'\bopcode\.extract_mod_o\(\)', 'X86Opcode.extractModO(opcode)', l)
    l = re.sub(r'\bopcode\.extract_mod_rm\(\)', 'X86Opcode.extractModRM(opcode)', l)
    l = re.sub(r'\bopcode\.extract_rex\(([^)]*)\)', r'_extractRex(opcode, \1)', l)
    l = re.sub(r'\bopcode\.extract_ll_mmmmm\(([^)]*)\)', r'_extractLLMmmmm(opcode, \1)', l)
    l = re.sub(r'\bopcode\.has_w\(\)', '_hasW(opcode)', l)
    l = re.sub(r'\bopcode\.v\b', 'opcode', l)
    l = re.sub(r'\bSupport::is_int_n<(\d+)>\(', r'_isIntN(\1, ', l)
    l = re.sub(r'\bSupport::is_uint_n<(\d+)>\(', r'_isUintN(\1, ', l)
    l = re.sub(r'\bSupport::min<\w+>\(', 'math.min(', l)
    l = re.sub(r'\bSupport::max<\w+>\(', 'math.max(', l)
    l = re.sub(r'\bSupport::test\(', '_test(', l)
    l = re.sub(r'\bSupport::(\w+)', lambda m: '_' + camel(m.group(1)), l)
    l = re.sub(r'\bsign_extend_int32<\w+>\(', '_signExtendInt32(', l)
    l = re.sub(r'\b(uint32_t|uint8_t|uint16_t|int32_t|FastUInt8)\(', lambda m: {'uint32_t':'_u32(','uint8_t':'_u8(','uint16_t':'_u16(','int32_t':'_i32(','FastUInt8':'('}[m.group(1)], l)
    l = re.sub(r'\b(uint64_t|int64_t|size_t)\(', '(', l)
    l = re.sub(r'(\d)u\b', r'\1', l)
    l = re.sub(r'(0x[0-9A-Fa-f]+)u\b', r'\1', l)
    l = re.sub(r'\b(uint32_t|int32_t|uint64_t|int64_t|bool|FastUInt8|size_t|uint8_t|InstId)\s+(\w+)\s*=', r'var \2 =', l)
    l = re.sub(r'\bconst Operand_& (\w+) = ', r'final \1 = ', l)
    l = re.sub(r'\bconst (Imm|Mem|Gp|Reg)& (\w+) = ', r'final \2 = ', l)
    l = re.sub(r'\bstd::swap\((\w+), (\w+)\);', r'{ final t = \1; \1 = \2; \2 = t; }', l)
    l = re.sub(r'\bASMJIT_UNLIKELY\((.*)\)\)', r'\1)', l)
    l = re.sub(r'\bASMJIT_LIKELY\((.*)\)\)', r'\1)', l)
    l = l.replace('&o', 'o') if re.search(r'rm_rel = &o\d', l) else l
    l = re.sub(r'\bwriter\.(\w+)\(', lambda m: '_w.' + camel(m.group(1)) + '(', l)
    # Method calls on operands -> camelCase.
    l = re.sub(r'\b(o\d|rm_rel!|imm0|imm1|m0|o3|o4|o5)\.([a-z_0-9]+)\(\)', lambda m: f'{m.group(1)}.{camel(m.group(2))}' + ('()' if m.group(2).startswith(('is_','has_')) else ''), l)
    l = re.sub(r'\b(o\d|rm_rel!|imm0|imm1|m0)\.([a-z_0-9]+)\(', lambda m: f'{m.group(1)}.{camel(m.group(2))}(', l)
    l = re.sub(r'\bcommon_info\.has_avx512_(\w+)\(\)', lambda m: '_ciHasAvx512' + camel('_' + m.group(1)) + '()', l)
    l = re.sub(r'\bcommon_info\.flags\(\)', 'ciFlags', l)
    l = re.sub(r'\bcommon_info\.([a-z_]+)\(\)', lambda m: '_ci' + camel('_' + m.group(1)) + '()', l)
    l = re.sub(r'\bcommon_info\.has_flag\(', '_ciHasFlag(', l)
    l = re.sub(r'\b(rm_rel|rm_info|rb_reg|rx_reg|op_reg|imm_value|imm_size|rel_offset|rel_size|mem_op_ao_mark|alt_opcode_of|inst_id|inst_info|pack_reg_and_vvvvv|encode_mod|encode_sib|is_implicit_mem|opcode_l_by_vmem|opcode_l_by_size|is_mmx_or_xmm|x86_should_use_movabs|is_jmp_or_call|base_address|virtual_offset|ll_by_reg_type_table|cdisp8_shl_table|vex_prefix_table|mod16_base_table|mod16_base_index_table|mem_info_table|x86_get_force_evex3_mask_in_last_bit)\b', lambda m: camel(m.group(1)), l)
    l = re.sub(r'\bis_32bit\(\)', '_is32Bit', l)
    l = re.sub(r'\bis_64bit\(\)', '_is64Bit', l)
    l = re.sub(r'\bregister_size\(\)', '_registerSize', l)
    l = re.sub(r'\b_address_override_mask\(\)', '_addressOverrideMask', l)
    l = re.sub(r'\bhas_encoding_option\(', '_hasEncodingOption(', l)
    # C-isms.
    l = l.replace('ASMJIT_UNLIKELY(', '(').replace('ASMJIT_LIKELY(', '(')
    l = re.sub(r'\bconst var\b', 'final', l)
    l = re.sub(r'\bconst InstOptions (\w+) =', r'const \1 =', l)
    l = re.sub(r'\bx86GetForceEvex3MaskInLastBit\(', '_forceEvex3MaskInLastBit(', l)
    l = re.sub(r'_ctzConst<X86InstDbFlags\.kVex>', '22 /* ctz(kVex) */', l)
    l = l.replace('EncodingOptions.kPredictedJumps', '_kPredictedJumps')
    l = re.sub(r'\bis_rex_invalid\(', '_isRexInvalid(', l)
    l = l.replace('_w.cursor()', '_w.cursor')
    l = re.sub(r'^(\s*)uint32_t (\w+);', r'\1int \2;', l)
    l = re.sub(r'\bimm([01])\.value\b', r'imm\1.imm', l)
    l = re.sub(r'\bopcode_(push|pop)_sreg_table\b', lambda m: '_opcode' + m.group(1).capitalize() + 'SregTable', l)
    l = re.sub(r'!instInfo\._alt_opcode_index', 'instInfo.altOpcode == 0', l)
    l = re.sub(r'\bcommon_info\.has_avx512_(\w+)\(\)', lambda m: '_ciHasAvx512' + camel('_' + m.group(1)) + '()', l)
    l = re.sub(r'\bcommon_info\.([a-z_]+)\(\)', lambda m: '_ci' + camel('_' + m.group(1)) + '()', l)
    l = re.sub(r'\b_extra_reg\.id\(\)', '_extraReg.id', l)
    l = re.sub(r'\b_extra_reg\.is_reg\(\)', '_extraReg.isReg()', l)
    l = re.sub(r'\(opReg & 0x8\) && _is32Bit', '(opReg & 0x8) != 0 && _is32Bit', l)
    l = re.sub(r'\bx86ShouldUseMovabs\(this, writer, ', '_shouldUseMovabs(', l)
    # Integer conditions.
    l = re.sub(r'\bif \(!\((\w+) & ([^()]+|\([^()]*\))\)\)', r'if ((\1 & \2) == 0)', l)
    l = re.sub(r'\bif \((\w+) & ([\w.]+|\([^()]*\))\)', r'if ((\1 & \2) != 0)', l)
    l = re.sub(r'\|\| \((\w+) & ([\w.]+)\)\)', r'|| (\1 & \2) != 0)', l)
    l = re.sub(r'!(o\d)\.x86RmSize\b', r'\1.x86RmSize == 0', l)
    l = re.sub(r'\bif \((o\d)\.x86RmSize\)', r'if (\1.x86RmSize != 0)', l)
    l = re.sub(r'(rmRel!\.offsetLo32) \|\|', r'\1 != 0 ||', l)
    l = re.sub(r'\+ \(([^()]+ != ?1)\)', r'+ _b(\1)', l)
    l = re.sub(r'\bif \(isign3 & ', 'if (0 != isign3 & ', l)
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
    if t == '[[fallthrough]];':
        nl = next_label(i)
        l = l.replace('[[fallthrough]];', f'{{ s = _S.{nl}; continue loop; }}')
    elif t == 'break;':
        l = l.replace('break;', '{ s = _S.InvalidInstruction; continue loop; }')
    else:
        l = re.sub(r'\bgoto (\w+);', lambda m: f'{{ s = _S.{m.group(1)}; continue loop; }}', l)
    l = expr(l)
    result.append(l)
    prev_code = l

open(sys.argv[2], 'w').write('\n'.join(result))
open(sys.argv[3], 'w').write('\n'.join(states))
print(len(result), 'lines', len(states), 'states')
