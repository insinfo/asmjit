_rep("""    err = _w.ensureSpace(this, multipleOpCount * 4);
    if ((err != Error::kOk)) {
      { state = _S.Failed; continue loop; }
    }
""", "")
_span("      case _S.EmitOp_Rel:\n", "      case _S.EmitOp_DispImm:", """      case _S.EmitOp_Rel:
  {
    if (rmRel!.isLabel() || rmRel!.isMem()) {
      final label = rmRel!.label!;
      final labelOffset = rmRel!.isLabel() ? 0 : rmRel!.offset;

      final bound = code.getLabelOffset(label);
      if (bound != null) {
        // Label bound to the current section.
        offsetValue = bound - _w.cursor + labelOffset;
        { state = _S.EmitOp_DispImm; continue loop; }
      }
      else {
        // Create a fixup referencing an non-bound label.
        _addFixup(label, _w.cursor, labelOffset, offsetFormat, instId);
        { state = _S.EmitOp; continue loop; }
      }
    }
  }

  if (rmRel!.isImm()) {
    final baseAddress = code.baseAddress;
    final targetOffset = rmRel!.imm;
    final codeOffset = _w.cursor;

    if (baseAddress == null) {
      // Create a new RelocEntry as we cannot calculate the offset right now.
      final re = code.newRelocEntry(RelocType.absToRel);

      re.sourceSectionId = code.text.id;
      re.sourceOffset = codeOffset;
      re.format = offsetFormat.copy();
      re.payload = rmRel!.imm + 4;
      { state = _S.EmitOp; continue loop; }
    }
    else {
      var pc = baseAddress + codeOffset;
      if (offsetFormat.type() == A64OffsetType.kAArch64_ADRP) {
        pc &= ~(4096 - 1);
      }
      offsetValue = targetOffset - pc;
      { state = _S.EmitOp_DispImm; continue loop; }
    }
  }

  { state = _S.InvalidInstruction; continue loop; }

      case _S.EmitOp_DispImm:""")
