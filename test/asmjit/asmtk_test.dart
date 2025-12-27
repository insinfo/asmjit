import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('AsmTokenizer', () {
    test('tokenizes simple instruction', () {
      final tokenizer = AsmTokenizer('mov rax, rbx');

      var token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'mov');

      token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'rax');

      token = tokenizer.next();
      expect(token.type, AsmTokenType.comma);

      token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'rbx');

      token = tokenizer.next();
      expect(token.type, AsmTokenType.end);
    });

    test('tokenizes hex number with 0x prefix', () {
      final tokenizer = AsmTokenizer('mov rax, 0x1234');

      tokenizer.next(); // mov
      tokenizer.next(); // rax
      tokenizer.next(); // ,

      final token = tokenizer.next();
      expect(token.type, AsmTokenType.u64);
      expect(token.intValue, 0x1234);
    });

    test('tokenizes decimal number', () {
      final tokenizer = AsmTokenizer('add rcx, 42');

      tokenizer.next(); // add
      tokenizer.next(); // rcx
      tokenizer.next(); // ,

      final token = tokenizer.next();
      expect(token.type, AsmTokenType.u64);
      expect(token.intValue, 42);
    });

    test('tokenizes memory operand brackets', () {
      final tokenizer = AsmTokenizer('[rax + rbx*4 + 8]');

      expect(tokenizer.next().type, AsmTokenType.lBracket);
      expect(tokenizer.next().text, 'rax');
      expect(tokenizer.next().type, AsmTokenType.add);
      expect(tokenizer.next().text, 'rbx');
      expect(tokenizer.next().type, AsmTokenType.mul);
      expect(tokenizer.next().intValue, 4);
      expect(tokenizer.next().type, AsmTokenType.add);
      expect(tokenizer.next().intValue, 8);
      expect(tokenizer.next().type, AsmTokenType.rBracket);
    });

    test('tokenizes label with colon', () {
      final tokenizer = AsmTokenizer('loop_start:');

      var token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'loop_start');

      token = tokenizer.next();
      expect(token.type, AsmTokenType.colon);
    });

    test('skips semicolon comments', () {
      final tokenizer = AsmTokenizer('mov rax, rbx ; this is a comment\nret');

      tokenizer.next(); // mov
      tokenizer.next(); // rax
      tokenizer.next(); // ,
      tokenizer.next(); // rbx

      var token = tokenizer.next();
      expect(token.type, AsmTokenType.newline);

      token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'ret');
    });

    test('handles newlines', () {
      final tokenizer = AsmTokenizer('mov rax, 1\nadd rax, 2');

      tokenizer.next(); // mov
      tokenizer.next(); // rax
      tokenizer.next(); // ,
      tokenizer.next(); // 1

      var token = tokenizer.next();
      expect(token.type, AsmTokenType.newline);

      token = tokenizer.next();
      expect(token.type, AsmTokenType.symbol);
      expect(token.text, 'add');
    });
  });

  group('AsmParser', () {
    test('parses simple mov instruction', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('mov rax, rbx');

      // Just verify it doesn't throw
      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses mov with immediate', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('mov rax, 42');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses multiple instructions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        push rbp
        mov rbp, rsp
        mov rax, rdi
        add rax, rsi
        pop rbp
        ret
      ''');

      expect(code.text.buffer.length, greaterThan(10));
    });

    test('parses labels and jumps', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        start:
          mov rax, 0
        loop:
          inc rax
          cmp rax, 10
          jl loop
          ret
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses memory operands', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        mov rax, [rbx]
        mov rax, [rbx + 8]
        mov rax, [rbx + rcx*4]
        mov rax, [rbx + rcx*8 + 16]
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses sized memory operands', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      // Note: mov mem, imm not supported, using mov mem, reg
      parser.parse('''
        mov rax, qword ptr [rbx]
        mov qword ptr [rbx + 8], rax
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses arithmetic instructions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        add rax, rbx
        sub rcx, rdx
        and rsi, rdi
        or r8, r9
        xor r10, r11
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses comparison and conditional jumps', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        cmp rax, 10
        je equal
        jne not_equal
        jl less
        jg greater
        jmp end
      equal:
      not_equal:
      less:
      greater:
      end:
        ret
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses shift instructions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        shl rax, 4
        shr rbx, cl
        sar rcx, 1
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses setcc instructions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        cmp rax, rbx
        sete al
        setne bl
        setl cl
        setg dl
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('parses cmovcc instructions', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      parser.parse('''
        cmp rax, rbx
        cmove rcx, rdx
        cmovne rsi, rdi
        cmovl r8, r9
        cmovg r10, r11
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('generates executable code', () {
      final code = CodeHolder();
      final asm = X86Assembler(code);
      final parser = AsmParser(asm);

      // Simple add function: int add(int a, int b) => a + b
      parser.parse('''
        mov rax, rdi
        add rax, rsi
        ret
      ''');

      final finalized = code.finalize();
      expect(finalized.textBytes.length, greaterThan(0));

      // Verify bytes look reasonable (MOV RAX, RDI = 48 89 F8)
      expect(finalized.textBytes[0], 0x48); // REX.W
    });
  });

  group('assembleString helper', () {
    test('assembles simple code', () {
      final code = assembleString('''
        mov rax, 42
        ret
      ''');

      expect(code.text.buffer.length, greaterThan(0));
    });
  });
}
