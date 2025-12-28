import 'package:test/test.dart';
import 'package:asmjit/src/asmjit/core/builder.dart';
import 'package:asmjit/asmjit.dart' as asmjit;

void main() {
  group('NodeList', () {
    test('starts empty', () {
      final list = NodeList();
      expect(list.isEmpty, isTrue);
      expect(list.length, 0);
      expect(list.first, isNull);
      expect(list.last, isNull);
    });

    test('append adds to end', () {
      final list = NodeList();
      final node1 = CommentNode('first');
      final node2 = CommentNode('second');

      list.append(node1);
      expect(list.length, 1);
      expect(list.first, node1);
      expect(list.last, node1);

      list.append(node2);
      expect(list.length, 2);
      expect(list.first, node1);
      expect(list.last, node2);
      expect(node1.next, node2);
      expect(node2.prev, node1);
    });

    test('prepend adds to beginning', () {
      final list = NodeList();
      final node1 = CommentNode('first');
      final node2 = CommentNode('second');

      list.prepend(node1);
      expect(list.first, node1);

      list.prepend(node2);
      expect(list.first, node2);
      expect(list.last, node1);
      expect(node2.next, node1);
      expect(node1.prev, node2);
    });

    test('insertAfter inserts correctly', () {
      final list = NodeList();
      final node1 = CommentNode('first');
      final node2 = CommentNode('second');
      final node3 = CommentNode('middle');

      list.append(node1);
      list.append(node2);
      list.insertAfter(node3, node1);

      expect(list.length, 3);
      expect(node1.next, node3);
      expect(node3.next, node2);
      expect(node3.prev, node1);
    });

    test('insertBefore inserts correctly', () {
      final list = NodeList();
      final node1 = CommentNode('first');
      final node2 = CommentNode('second');
      final node3 = CommentNode('middle');

      list.append(node1);
      list.append(node2);
      list.insertBefore(node3, node2);

      expect(list.length, 3);
      expect(node1.next, node3);
      expect(node3.next, node2);
      expect(node3.prev, node1);
    });

    test('remove removes correctly', () {
      final list = NodeList();
      final node1 = CommentNode('first');
      final node2 = CommentNode('second');
      final node3 = CommentNode('third');

      list.append(node1);
      list.append(node2);
      list.append(node3);

      list.remove(node2);
      expect(list.length, 2);
      expect(node1.next, node3);
      expect(node3.prev, node1);

      list.remove(node1);
      expect(list.length, 1);
      expect(list.first, node3);
      expect(list.last, node3);

      list.remove(node3);
      expect(list.isEmpty, isTrue);
    });

    test('iterate over nodes', () {
      final list = NodeList();
      list.append(CommentNode('a'));
      list.append(CommentNode('b'));
      list.append(CommentNode('c'));

      final comments =
          list.nodes.whereType<CommentNode>().map((n) => n.text).toList();
      expect(comments, ['a', 'b', 'c']);
    });
  });

  group('InstNode', () {
    test('creates instruction node', () {
      final operands = [asmjit.rax, Imm(42)];
      final inst = InstNode(0x01, operands);

      expect(inst.nodeType, NodeType.inst);
      expect(inst.instId, 0x01);
      expect(inst.opCount, 2);
      expect(inst.isInst, isTrue);
      expect(inst.isCode, isTrue);
    });
  });

  group('LabelNode', () {
    test('creates label node', () {
      final label = asmjit.Label(5);
      final node = LabelNode(label);

      expect(node.nodeType, NodeType.label);
      expect(node.labelId, 5);
      expect(node.isLabel, isTrue);
    });
  });

  group('AlignNode', () {
    test('creates align node', () {
      final node = AlignNode(AlignMode.code, 16);

      expect(node.nodeType, NodeType.align);
      expect(node.alignMode, AlignMode.code);
      expect(node.alignment, 16);
    });
  });

  group('EmbedDataNode', () {
    test('creates data node', () {
      final data = [0x48, 0x89, 0xE5];
      final node = EmbedDataNode(data);

      expect(node.nodeType, NodeType.embedData);
      expect(node.data, data);
      expect(node.isData, isTrue);
    });
  });

  group('CommentNode', () {
    test('creates comment node', () {
      final node = CommentNode('This is a comment');

      expect(node.nodeType, NodeType.comment);
      expect(node.text, 'This is a comment');
      expect(node.isRemovable, isTrue);
    });
  });

  group('SentinelNode', () {
    test('creates sentinel node', () {
      final node = SentinelNode(SentinelType.funcEnd);

      expect(node.nodeType, NodeType.sentinel);
      expect(node.sentinelType, SentinelType.funcEnd);
    });
  });

  group('Operand classes', () {
    test('Reg (BaseReg)', () {
      final op = asmjit.rcx;
      expect(op.isReg, isTrue);
      expect(op.isMem, isFalse);
      expect(op.isImm, isFalse);
    });

    test('Imm', () {
      final op = Imm(0x1234);
      expect(op.isReg, isFalse);
      expect(op.isImm, isTrue);
      expect(op.value, 0x1234);
    });

    test('LabelOp', () {
      final label = asmjit.Label(10);
      final op = LabelOp(label);
      expect(op.isLabel, isTrue);
      expect(op.label.id, 10);
    });
  });

  group('NodeList filtering', () {
    test('filter instructions only', () {
      final list = NodeList();
      list.append(CommentNode('start'));
      list.append(InstNode(1, []));
      list.append(LabelNode(asmjit.Label(0)));
      list.append(InstNode(2, []));
      list.append(CommentNode('end'));

      final instructions = list.instructions.toList();
      expect(instructions.length, 2);
      expect(instructions[0].instId, 1);
      expect(instructions[1].instId, 2);
    });

    test('filter labels only', () {
      final list = NodeList();
      list.append(LabelNode(asmjit.Label(1)));
      list.append(InstNode(1, []));
      list.append(LabelNode(asmjit.Label(2)));

      final labels = list.labels.toList();
      expect(labels.length, 2);
      expect(labels[0].labelId, 1);
      expect(labels[1].labelId, 2);
    });
  });

  group('BaseBuilder', () {
    test('creates builder with empty nodes', () {
      final builder = BaseBuilder();
      expect(builder.nodeCount, 0);
      expect(builder.instCount, 0);
    });

    test('newLabel creates unique labels', () {
      final builder = BaseBuilder();
      final l1 = builder.newLabel();
      final l2 = builder.newLabel();
      final l3 = builder.newLabel();

      expect(l1.id, 0);
      expect(l2.id, 1);
      expect(l3.id, 2);
    });

    test('inst adds instruction node', () {
      final builder = BaseBuilder();
      builder.inst(0x10, [asmjit.rax, Imm(42)]);
      builder.inst(0x20, []);

      expect(builder.nodeCount, 2);
      expect(builder.instCount, 2);
      expect(builder.usedInstIds, {0x10, 0x20});
    });

    test('label binds a label', () {
      final builder = BaseBuilder();
      final l = builder.newLabel();
      builder.label(l);

      expect(builder.definedLabels.length, 1);
      expect(builder.definedLabels[0].id, l.id);
    });

    test('comment adds comment node', () {
      final builder = BaseBuilder();
      builder.comment('Hello world');

      expect(builder.nodeCount, 1);
      expect(builder.nodes.first is CommentNode, isTrue);
      expect((builder.nodes.first as CommentNode).text, 'Hello world');
    });

    test('embedData adds data node', () {
      final builder = BaseBuilder();
      builder.embedData([1, 2, 3, 4]);

      expect(builder.nodeCount, 1);
      expect(builder.nodes.first is EmbedDataNode, isTrue);
    });

    test('clear resets builder', () {
      final builder = BaseBuilder();
      builder.inst(1, []);
      builder.comment('test');
      builder.newLabel();

      builder.clear();

      expect(builder.nodeCount, 0);
      expect(builder.newLabel().id, 0); // counter also reset
    });
  });

  group('Serialization', () {
    test('serializeNodes calls context methods in order', () {
      final builder = BaseBuilder();
      final l = builder.newLabel();

      builder.comment('Start');
      builder.label(l);
      builder.inst(0x01, [asmjit.rax]);
      builder.align(AlignMode.code, 16);
      builder.embedData([0x90]);
      builder.sentinel(SentinelType.funcEnd);

      final ctx = _TestSerializerContext();
      serializeNodes(builder.nodes, ctx);

      expect(ctx.events, [
        'comment:Start',
        'label:L0',
        'inst:1',
        'align:code:16',
        'embedData:1',
        'sentinel:funcEnd',
      ]);
    });
  });
}

class _TestSerializerContext extends SerializerContext {
  final List<String> events = [];

  @override
  void onLabel(asmjit.Label label) {
    events.add('label:L${label.id}');
  }

  @override
  void onInst(int instId, List<Operand> operands, int options) {
    events.add('inst:$instId');
  }

  @override
  void onAlign(AlignMode mode, int alignment) {
    events.add('align:${mode.name}:$alignment');
  }

  @override
  void onEmbedData(List<int> data, int typeSize) {
    events.add('embedData:${data.length}');
  }

  @override
  void onComment(String text) {
    events.add('comment:$text');
  }

  @override
  void onSentinel(SentinelType type) {
    events.add('sentinel:${type.name}');
  }
}
