def _rep(old, new, count=1):
    global body
    if body.count(old) != count:
        raise SystemExit(f'patch: expected {count} occurrence(s) of:\n{old[:200]}\nfound {body.count(old)}')
    body = body.replace(old, new)

def _span(start, end, new):
    global body
    i = body.index(start)
    j = body.index(end, i) + len(end)
    body = body[:i] + new + body[j:]

# [ABSOLUTE | DISP32]: the port's CodeHolder has no base address
# (`Globals::kNoBaseAddress`), so relative addressing of an absolute target
# needs an AbsToRel relocation, which the port does not support yet.
_span("      Mem::AddrType addr_type = rmRel!.addrType;\n", "        var baseAddress = code()->baseAddress();\n",
"      var addr_type = rmRel!.addrType;\n      relOffset = rmRel!.offsetLo32;\n\n      if (_is32Bit) {\n        // Explicit relative addressing doesn't work in 32-bit mode.\n        if (addr_type == _Addr.kRel)\n          { s = _S.InvalidAddress; continue loop; }\n\n        _w.emit8(encodeMod(0, opReg, 5));\n        _w.emit32uLe(_u32(relOffset));\n      }\n      else {\n        var is_offset_int32 = rmRel!.offsetHi32 == (relOffset >> 31);\n        var is_offset_uint32 = rmRel!.offsetHi32 == 0;\n        final baseAddress = code.baseAddress;\n")
_span("        if (addr_type == _Addr.kDefault) {\n          if (baseAddress == Globals::kNoBaseAddress) {", "        // Handle unsigned 32-bit address that doesn't work with sign extension.",
"""        if (addr_type == _Addr.kDefault) {
          if (baseAddress == null) {
            // Prefer absolute addressing mode if the offset is 32-bit.
            addr_type = is_offset_int32 || is_offset_uint32 ? _Addr.kAbs : _Addr.kRel;
          }
          else {
            // Prefer absolute addressing mode if FS|GS segment override is present.
            var has_fs_gs = rmRel!.segmentId >= _kSegFs;
            // Prefer absolute addressing mode if this is LEA with 32-bit immediate.
            var is_lea_32 = (instId == X86InstId.kLea) && (is_offset_int32 || is_offset_uint32);

            addr_type = has_fs_gs || is_lea_32 ? _Addr.kAbs : _Addr.kRel;
          }
        }

        if (addr_type == _Addr.kRel) {
          var kModRel32Size = 5;
          var virtualOffset = _w.cursor + immSize + kModRel32Size;

          if (baseAddress == null) {
            // Create a new RelocEntry as we cannot calculate the offset right now.
            final re = code.newRelocEntry(RelocType.absToRel);

            _w.emit8(encodeMod(0, opReg, 5));

            re.sourceSectionId = section.id;
            re.sourceOffset = instStart;
            re.format
              ..resetToSimpleValue(OffsetType.kSignedOffset, 4)
              ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
            re.payload = rmRel!.offset;

            _w.emit32uLe(0);
            _w.emitImmediate(immValue, immSize);
            { s = _S.EmitDone; continue loop; }
          }
          else {
            var rip64 = baseAddress + virtualOffset;
            var rel64 = rmRel!.offset - rip64;

            if (_isIntN(32, rel64)) {
              _w.emit8(encodeMod(0, opReg, 5));
              _w.emit32uLe(_u32(rel64 & 0xFFFFFFFF));
              _w.emitImmediate(immValue, immSize);
              { s = _S.EmitDone; continue loop; }
            }
            else {
              // We must check the original address type as we have modified
              // `addr_type`. We failed if the original address type is 'rel'.
              if (rmRel!.isAddrRel())
                { s = _S.InvalidAddress; continue loop; }
            }
          }
        }

        // Handle unsigned 32-bit address that doesn't work with sign extension.""")
_rep("          if (*memOpAoMark != 0x67) {", "          if (_w.at(memOpAoMark) != 0x67) {")
_rep("              var rex = *memOpAoMark;\n              if ((rex & _kByteRex) != 0) {\n                rex &= (~_kByteRexW) & 0xFF;\n                *memOpAoMark = _u8(rex);",
     "              var rex = _w.at(memOpAoMark);\n              if ((rex & _kByteRex) != 0) {\n                rex &= (~_kByteRexW) & 0xFF;\n                _w.setAt(memOpAoMark, _u8(rex));")

# [LABEL|RIP + DISP32] (64-bit).
_span("        if ((rmInfo & _kMemInfoBaseLabel) != 0) {\n          // [RIP].\n          var base_label_id = rmRel!.baseId;", "            relSize = 4;\n            { s = _S.EmitRel; continue loop; }\n          }\n        }",
"""        if ((rmInfo & _kMemInfoBaseLabel) != 0) {
          // [RIP].
          label = rmRel!.label;
          relOffset -= (4 + immSize);

          final bound = code.isLabelBoundTo(label!, section.id)
          ? code.getLabelOffset(label!)
          : null;
          if (bound != null) {
            // Label bound to the current section.
            relOffset += _i32(bound - _w.cursor);
            _w.emit32uLe(_u32(relOffset));
          }
          else {
            // Non-bound label or label bound to a different section.
            relSize = 4;
            { s = _S.EmitRel; continue loop; }
          }
        }""")

# EmitJmpCall: locals shared with the hoisted EmitJmpCallRel.
_rep("    var ip = (_w.offsetFrom(_buffer_data));\n    var rel32 = 0;\n    var opcode8 = altOpcodeOf(instInfo);\n\n    var inst8_size = 1 + 1;",
     "    var ip = _w.cursor;\n    rel32 = 0;\n    opcode8 = altOpcodeOf(instInfo);\n\n    inst8_size = 1 + 1;")
_rep("    var inst32_size = 1 + 4;", "    inst32_size = 1 + 4;")
_span("      var label_id = rmRel!.labelId;\n      if (!_code->is_label_valid(label_id)) {", "        { s = _S.EmitJmpCallRel; continue loop; }\n      }",
"""      label = rmRel!.label;
      final bound = code.isLabelBoundTo(label!, section.id)
          ? code.getLabelOffset(label!)
          : null;
      if (bound != null) {
        // Label bound to the current section.
        rel32 = _u32((bound - ip - inst32_size) & 0xFFFFFFFF);
        { s = _S.EmitJmpCallRel; continue loop; }
      }""")
_rep("        if (opcode8 && (!opcode || _test(options, _IO.kShortForm))) {", "        if (opcode8 != 0 && (opcode == 0 || _test(options, _IO.kShortForm))) {")
_rep("          if (!opcode || _test(options, _IO.kShortForm))\n            { s = _S.InvalidDisplacement; continue loop; }",
     "          if (opcode == 0 || _test(options, _IO.kShortForm))\n            { s = _S.InvalidDisplacement; continue loop; }")
# Jump to an absolute address: upstream needs an AbsToRel relocation (no base address).
_span("    if (rmRel!.isImm()) {\n      var baseAddress = code()->baseAddress();", "    // Not Label|Imm -> Invalid.",
"""    if (rmRel!.isImm()) {
      final baseAddress = code.baseAddress;
      var jump_address = rmRel!.imm;

      // If the base-address is known calculate a relative displacement and check if it fits in 32 bits (which is
      // always true in 32-bit mode). Emit relative displacement as it was a bound label if all checks are ok.
      if (baseAddress != null) {
        var rel64 = jump_address - (ip + baseAddress) - inst32_size;
        if (_isIntN(32, rel64)) {
          rel32 = _u32(rel64 & 0xFFFFFFFF);
          { s = _S.EmitJmpCallRel; continue loop; }
        }
        else {
          // Relative displacement exceeds 32-bits - relocator can only insert trampoline for jmp/call, but not
          // for jcc/jecxz.
          if (!isJmpOrCall(instId))
            { s = _S.InvalidDisplacement; continue loop; }
        }
      }

      final re = code.newRelocEntry(RelocType.absToRel);

      re.sourceOffset = instStart;
      re.sourceSectionId = section.id;
      re.payload = jump_address;

      if (opcode != 0) {
        // 64-bit: Emit REX prefix so the instruction can be patched later. REX prefix does nothing if not patched,
        // but allows to patch the instruction to use MOD/M and to point to a memory where the final 64-bit address
        // is stored.
        if (!_is32Bit && isJmpOrCall(instId)) {
          if (rex == 0) _w.emit8(_kByteRex);

          code.addAddressToAddressTable(jump_address);

          re.relocType = RelocType.x64AddressEntry;
        }

        _w.emit8If(0x0F, (opcode & X86Opcode.kMM_Mask) != 0); // Emit 0F prefix.
        _w.emit8(opcode); // Emit opcode.
        _w.emit8If(encodeMod(3, opReg, 0), opReg != 0); // Emit MOD.
        re.format
          ..resetToSimpleValue(OffsetType.kSignedOffset, 4)
          ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
        _w.emit32uLe(0); // Emit DISP32.
      }
      else {
        _w.emit8(opcode8); // Emit opcode.
        re.format
          ..resetToSimpleValue(OffsetType.kSignedOffset, 1)
          ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
        _w.emit8(0); // Emit DISP8 (zero).
      }
      { s = _S.EmitDone; continue loop; }
    }

    // Not Label|Imm -> Invalid.""")
_rep("    if (_isIntN(8, _i32(rel32 + inst32_size - inst8_size)) && opcode8 && !_test(options, _IO.kLongForm)) {",
     "    if (_isIntN(8, _i32(rel32 + inst32_size - inst8_size)) && opcode8 != 0 && !_test(options, _IO.kLongForm)) {")
_rep("      if (!opcode || _test(options, _IO.kShortForm))\n        { s = _S.InvalidDisplacement; continue loop; }\n\n      options &= ~_IO.kShortForm;",
     "      if (opcode == 0 || _test(options, _IO.kShortForm))\n        { s = _S.InvalidDisplacement; continue loop; }\n\n      options &= ~_IO.kShortForm;")

# EmitRel: the label fixup (displacement = target - offset + rel_offset).
_span("    // Chain with label.\n    var offset = (_w.offsetFrom(_buffer_data));", "    _w.emitZeros(relSize);\n  }",
"""    // Chain with label.
    final offset = _w.cursor;
    final of = OffsetFormat()
      ..resetToSimpleValue(OffsetType.kSignedOffset, relSize);

    code.newFixup(label!, section.id, offset, relOffset, of);

    // Emit dummy zeros, must be patched later when the reference becomes known.
    _w.emitZeros(relSize);
  }""")
