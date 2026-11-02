_rep("        multipleOpCount = encodeMovSequence64(multipleOpData, imm_value, o0.id & 31, x);",
     "        {\n          final seq = A64Encoder.encodeMovSequence64(imm_value, o0.id & 31, x);\n          multipleOpData..clear()..addAll(seq);\n          multipleOpCount = seq.length;\n        }")
_rep("var a_hi_id = _u32(opcode.get() & _B(29) ? kZR : kSP);", "var a_hi_id = (opcode.get() & _B(29)) != 0 ? kZR : kSP;")
_rep("if (!(opcode.get() & _B(29))) {", "if ((opcode.get() & _B(29)) == 0) {")
_rep("if (!(imm & _B(15)))", "if ((imm & _B(15)) == 0)", 2)
# pick_fp_opcode(..., &opcode, &sz): `sz` is the output.
_rep("""          int sz = 0;

          if (!pickFpOpcode(o0, op_data.element_scalar_op, kHF_D, op_data.element_vector_op, kHF_D, opcode, szOut))
            { state = _S.InvalidInstruction; continue loop; }
""", """          final szOut = [0];

          if (!pickFpOpcode(o0, op_data.element_scalar_op, kHF_D, op_data.element_vector_op, kHF_D, opcode, szOut))
            { state = _S.InvalidInstruction; continue loop; }
          final sz = szOut[0];
""")
_rep("""          int sz = 0;
          if (!pickFpOpcode(o0, op_data.scalar_fp_op, kHF_0, op_data.vector_fp_op, kHF_0, opcode, szOut))
            { state = _S.InvalidInstruction; continue loop; }
""", """          final szOut = [0];
          if (!pickFpOpcode(o0, op_data.scalar_fp_op, kHF_0, op_data.vector_fp_op, kHF_0, opcode, szOut))
            { state = _S.InvalidInstruction; continue loop; }
          final sz = szOut[0];
""")
_rep("""          double fp_value;
          if (o1.isDouble())
            fp_value = o1.immAsDouble;
          else if (o1.isInt32())
            fp_value = o1.immI32;""", """          double fp_value;
          if (o1.isDouble())
            fp_value = o1.immAsDouble;
          else if (o1.isInt32())
            fp_value = o1.immI32.toDouble();""")
_rep("          if (!isFp64Imm8(fp_value))", "          if (!isFp64Imm8(doubleBits(fp_value)))")
_rep("          var imm8 = _u32(encodeFp64ToImm8(fp_value));", "          var imm8 = _u32(encodeFp64ToImm8(doubleBits(fp_value)));")
