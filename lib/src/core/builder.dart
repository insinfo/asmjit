/// AsmJit Builder - Intermediate Representation
///
/// Port of asmjit/core/builder.h - provides a node-based IR
/// that can be modified before serialization to machine code.

import 'labels.dart';
import 'operand.dart';

/// Type of node in the builder.
enum NodeType {
  /// Invalid node.
  none,

  /// Instruction node.
  inst,

  /// Section node.
  section,

  /// Label node.
  label,

  /// Alignment node.
  align,

  /// Embedded data node.
  embedData,

  /// Embedded label node.
  embedLabel,

  /// Constant pool node.
  constPool,

  /// Comment node.
  comment,

  /// Sentinel node (marks end of function, etc).
  sentinel,

  /// Jump node (for compiler).
  jump,

  /// Function node.
  func,

  /// Function return node.
  funcRet,

  /// Function call node.
  invoke,
}

/// Flags that describe node properties.
class NodeFlags {
  static const int none = 0;

  /// Node is code that can be executed.
  static const int isCode = 1 << 0;

  /// Node is data that cannot be executed.
  static const int isData = 1 << 1;

  /// Node is informative only (comment, etc).
  static const int isInformative = 1 << 2;

  /// Node can be safely removed if unreachable.
  static const int isRemovable = 1 << 3;

  /// Node has no effect when executed.
  static const int hasNoEffect = 1 << 4;

  /// Node is an instruction or acts as one.
  static const int actsAsInst = 1 << 5;

  /// Node is a label or acts as one.
  static const int actsAsLabel = 1 << 6;

  /// Node is active (part of code).
  static const int isActive = 1 << 7;
}

/// Base class for all builder nodes.
class BaseNode {
  /// Previous node in the list.
  BaseNode? prev;

  /// Next node in the list.
  BaseNode? next;

  /// Node type.
  final NodeType nodeType;

  /// Node flags.
  int flags;

  /// Node position (for analysis passes).
  int position = 0;

  /// User data (for custom use).
  Object? userData;

  /// Inline comment.
  String? comment;

  BaseNode(this.nodeType, [this.flags = NodeFlags.none]);

  /// Check if node is an instruction.
  bool get isInst => flags & NodeFlags.actsAsInst != 0;

  /// Check if node is a label.
  bool get isLabel => flags & NodeFlags.actsAsLabel != 0;

  /// Check if node is code.
  bool get isCode => flags & NodeFlags.isCode != 0;

  /// Check if node is data.
  bool get isData => flags & NodeFlags.isData != 0;

  /// Check if node is removable.
  bool get isRemovable => flags & NodeFlags.isRemovable != 0;

  /// Check if node is active.
  bool get isActive => flags & NodeFlags.isActive != 0;

  /// Set inline comment.
  void setComment(String text) {
    comment = text;
  }
}

/// Instruction node.
class InstNode extends BaseNode {
  /// Instruction ID.
  final int instId;

  /// Instruction operands.
  final List<Operand> operands;

  /// Instruction options.
  int options;

  InstNode(this.instId, this.operands, {this.options = 0})
      : super(NodeType.inst, NodeFlags.isCode | NodeFlags.actsAsInst);

  /// Number of operands.
  int get opCount => operands.length;

  /// Check if instruction has no operands.
  bool get hasNoOperands => operands.isEmpty;

  @override
  String toString() => 'InstNode($instId, $operands)';
}

/// Label node.
class LabelNode extends BaseNode {
  /// The label this node represents.
  final Label label;

  LabelNode(this.label)
      : super(NodeType.label, NodeFlags.hasNoEffect | NodeFlags.actsAsLabel);

  /// Label ID.
  int get labelId => label.id;

  @override
  String toString() => 'LabelNode(L${label.id})';
}

/// Alignment node.
class AlignNode extends BaseNode {
  /// Alignment mode (code or data).
  final AlignMode alignMode;

  /// Alignment in bytes.
  final int alignment;

  AlignNode(this.alignMode, this.alignment)
      : super(NodeType.align, NodeFlags.isCode | NodeFlags.hasNoEffect);

  @override
  String toString() => 'AlignNode($alignMode, $alignment bytes)';
}

/// Align mode.
enum AlignMode {
  /// Code alignment.
  code,

  /// Data alignment.
  data,

  /// Zero-fill alignment.
  zero,
}

/// Embedded data node.
class EmbedDataNode extends BaseNode {
  /// Data bytes.
  final List<int> data;

  /// Item size (1, 2, 4, 8 bytes).
  final int typeSize;

  EmbedDataNode(this.data, {this.typeSize = 1})
      : super(NodeType.embedData, NodeFlags.isData);

  @override
  String toString() => 'EmbedDataNode(${data.length} bytes)';
}

/// Comment node.
class CommentNode extends BaseNode {
  /// Comment text.
  final String text;

  CommentNode(this.text)
      : super(
            NodeType.comment, NodeFlags.isInformative | NodeFlags.isRemovable);

  @override
  String toString() => 'CommentNode("$text")';
}

/// Sentinel node (marks boundaries).
class SentinelNode extends BaseNode {
  /// Sentinel type.
  final SentinelType sentinelType;

  SentinelNode([this.sentinelType = SentinelType.unknown])
      : super(NodeType.sentinel, NodeFlags.isInformative);

  @override
  String toString() => 'SentinelNode($sentinelType)';
}

/// Type of sentinel.
enum SentinelType {
  unknown,
  funcEnd,
}

/// Node list - a double-linked list of nodes.
class NodeList {
  BaseNode? _first;
  BaseNode? _last;
  int _count = 0;

  /// First node.
  BaseNode? get first => _first;

  /// Last node.
  BaseNode? get last => _last;

  /// Number of nodes.
  int get length => _count;

  /// Check if list is empty.
  bool get isEmpty => _first == null;

  /// Check if list is not empty.
  bool get isNotEmpty => _first != null;

  /// Clear the list.
  void clear() {
    _first = null;
    _last = null;
    _count = 0;
  }

  /// Add a node at the end.
  void append(BaseNode node) {
    node.prev = _last;
    node.next = null;

    if (_last != null) {
      _last!.next = node;
    } else {
      _first = node;
    }
    _last = node;
    _count++;
  }

  /// Add a node at the beginning.
  void prepend(BaseNode node) {
    node.prev = null;
    node.next = _first;

    if (_first != null) {
      _first!.prev = node;
    } else {
      _last = node;
    }
    _first = node;
    _count++;
  }

  /// Insert a node after ref.
  void insertAfter(BaseNode node, BaseNode ref) {
    node.prev = ref;
    node.next = ref.next;

    if (ref.next != null) {
      ref.next!.prev = node;
    } else {
      _last = node;
    }
    ref.next = node;
    _count++;
  }

  /// Insert a node before ref.
  void insertBefore(BaseNode node, BaseNode ref) {
    node.prev = ref.prev;
    node.next = ref;

    if (ref.prev != null) {
      ref.prev!.next = node;
    } else {
      _first = node;
    }
    ref.prev = node;
    _count++;
  }

  /// Remove a node.
  void remove(BaseNode node) {
    if (node.prev != null) {
      node.prev!.next = node.next;
    } else {
      _first = node.next;
    }

    if (node.next != null) {
      node.next!.prev = node.prev;
    } else {
      _last = node.prev;
    }

    node.prev = null;
    node.next = null;
    _count--;
  }

  /// Iterate over all nodes.
  Iterable<BaseNode> get nodes sync* {
    var current = _first;
    while (current != null) {
      yield current;
      current = current.next;
    }
  }

  /// Iterate over instruction nodes only.
  Iterable<InstNode> get instructions sync* {
    var current = _first;
    while (current != null) {
      if (current is InstNode) {
        yield current;
      }
      current = current.next;
    }
  }

  /// Iterate over label nodes only.
  Iterable<LabelNode> get labels sync* {
    var current = _first;
    while (current != null) {
      if (current is LabelNode) {
        yield current;
      }
      current = current.next;
    }
  }
}

/// Abstract operand class for builder.
class Operand {
  /// Check if operand is a register.
  bool get isReg => false;

  /// Check if operand is memory.
  bool get isMem => false;

  /// Check if operand is immediate.
  bool get isImm => false;

  /// Check if operand is a label.
  bool get isLabel => false;
}

/// Register operand.
class RegOperand extends Operand {
  final BaseReg reg;

  RegOperand(this.reg);

  @override
  bool get isReg => true;

  @override
  String toString() => reg.toString();
}

/// Immediate operand.
class ImmOperand extends Operand {
  final int value;

  ImmOperand(this.value);

  @override
  bool get isImm => true;

  @override
  String toString() => value.toString();
}

/// Label operand.
class LabelOperand extends Operand {
  final Label label;

  LabelOperand(this.label);

  @override
  bool get isLabel => true;

  @override
  String toString() => 'L${label.id}';
}

/// Memory operand.
class MemOperand extends Operand {
  final Object mem; // X86Mem or similar

  MemOperand(this.mem);

  @override
  bool get isMem => true;

  @override
  String toString() => '[$mem]';
}

/// Base builder - manages a list of nodes.
///
/// This is the foundation for the builder pattern in AsmJit.
/// It allows recording instructions as nodes before serialization.
class BaseBuilder {
  /// The node list.
  final NodeList nodes = NodeList();

  /// Label counter for creating new labels.
  int _labelCounter = 0;

  /// Clear all nodes.
  void clear() {
    nodes.clear();
    _labelCounter = 0;
  }

  /// Create a new label.
  Label newLabel() {
    return Label(_labelCounter++);
  }

  /// Add an instruction node.
  InstNode inst(int instId, List<Operand> operands, {int options = 0}) {
    final node = InstNode(instId, operands, options: options);
    nodes.append(node);
    return node;
  }

  /// Add a label node (bind a label here).
  LabelNode label(Label label) {
    final node = LabelNode(label);
    nodes.append(node);
    return node;
  }

  /// Add alignment.
  AlignNode align(AlignMode mode, int alignment) {
    final node = AlignNode(mode, alignment);
    nodes.append(node);
    return node;
  }

  /// Embed data bytes.
  EmbedDataNode embedData(List<int> data, {int typeSize = 1}) {
    final node = EmbedDataNode(data, typeSize: typeSize);
    nodes.append(node);
    return node;
  }

  /// Add a comment.
  CommentNode comment(String text) {
    final node = CommentNode(text);
    nodes.append(node);
    return node;
  }

  /// Add a sentinel.
  SentinelNode sentinel([SentinelType type = SentinelType.unknown]) {
    final node = SentinelNode(type);
    nodes.append(node);
    return node;
  }

  /// Get all instruction IDs used.
  Set<int> get usedInstIds {
    final ids = <int>{};
    for (final node in nodes.instructions) {
      ids.add(node.instId);
    }
    return ids;
  }

  /// Get all labels defined.
  List<Label> get definedLabels {
    return nodes.labels.map((n) => n.label).toList();
  }

  /// Count of nodes.
  int get nodeCount => nodes.length;

  /// Count of instructions.
  int get instCount => nodes.instructions.length;
}

/// A serialization context for IR.
///
/// Subclasses can implement this to serialize the IR
/// to a specific assembler.
abstract class SerializerContext {
  /// Called when a label is encountered.
  void onLabel(Label label);

  /// Called when an instruction is encountered.
  void onInst(int instId, List<Operand> operands, int options);

  /// Called when alignment is encountered.
  void onAlign(AlignMode mode, int alignment);

  /// Called when embedded data is encountered.
  void onEmbedData(List<int> data, int typeSize);

  /// Called when a comment is encountered.
  void onComment(String text);

  /// Called when a sentinel is encountered.
  void onSentinel(SentinelType type);
}

/// Serialize a node list to a context.
void serializeNodes(NodeList nodes, SerializerContext ctx) {
  for (final node in nodes.nodes) {
    switch (node.nodeType) {
      case NodeType.label:
        ctx.onLabel((node as LabelNode).label);
      case NodeType.inst:
        final inst = node as InstNode;
        ctx.onInst(inst.instId, inst.operands, inst.options);
      case NodeType.align:
        final align = node as AlignNode;
        ctx.onAlign(align.alignMode, align.alignment);
      case NodeType.embedData:
        final data = node as EmbedDataNode;
        ctx.onEmbedData(data.data, data.typeSize);
      case NodeType.comment:
        ctx.onComment((node as CommentNode).text);
      case NodeType.sentinel:
        ctx.onSentinel((node as SentinelNode).sentinelType);
      default:
        // Other node types are ignored during serialization
        break;
    }
  }
}
