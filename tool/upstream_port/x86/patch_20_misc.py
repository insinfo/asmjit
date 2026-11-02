# EmitModSib_LabelRip_X86 is reachable only in 32-bit mode.
_i = body.index("      case _S.EmitModSib_LabelRip_X86:")
_j = body.index("      case _S.EmitModVSib:", _i)
body = body[:_i] + "      case _S.EmitModSib_LabelRip_X86:\n        // 32-bit mode only (the port targets x64).\n        { s = _S.InvalidInstruction; continue loop; }\n" + body[_j:]
_rep("""      static_assert(_u32(_IO.kX86_RZ_SAE) == kLLMask11,
                    "This code requires InstOptions::X86_RZ_SAE to match kLLMask11 to work properly");""", "      assert(_IO.kX86_RZ_SAE == kLLMask11);", body.count('static_assert(_u32(_IO.kX86_RZ_SAE) == kLLMask11,'))
_rep("""    ASMJIT_ASSERT((opcode  & X86Opcode.kMM_Mask) == 0 ||
                  (opcode  & X86Opcode.kMM_Mask) == X86Opcode.kMM_0F);""", """    // ASMJIT_ASSERT((opcode  & X86Opcode.kMM_Mask) == 0 ||
    //               (opcode  & X86Opcode.kMM_Mask) == X86Opcode.kMM_0F);""")
