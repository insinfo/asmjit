/// Double linked list used by `JitAllocator`.
///
/// Ported from asmjit/support/arenalist.h (`ArenaListNode`, `ArenaList`).
library;

/// A node of [ArenaList] (`ArenaListNode<NodeT>`).
mixin ArenaListNode<N extends ArenaListNode<N>> {
  static const int kNodeIndexPrev = 0;
  static const int kNodeIndexNext = 1;

  /// `_list_nodes[0]` is the previous node, `_list_nodes[1]` the next one.
  final List<N?> listNodes = List<N?>.filled(2, null);

  bool get hasPrev => listNodes[kNodeIndexPrev] != null;
  bool get hasNext => listNodes[kNodeIndexNext] != null;

  N? get prev => listNodes[kNodeIndexPrev];
  N? get next => listNodes[kNodeIndexNext];
}

/// Double linked list (`ArenaList<NodeT>`).
class ArenaList<N extends ArenaListNode<N>> {
  static const int kNodeIndexFirst = 0;
  static const int kNodeIndexLast = 1;

  final List<N?> _nodes = List<N?>.filled(2, null);

  void reset() {
    _nodes[0] = null;
    _nodes[1] = null;
  }

  bool get isEmpty => _nodes[0] == null;

  N? get first => _nodes[kNodeIndexFirst];
  N? get last => _nodes[kNodeIndexLast];

  void _addNode(N node, int dir) {
    final prev = _nodes[dir];
    node.listNodes[dir ^ 1] = prev;
    _nodes[dir] = node;
    if (prev != null) {
      prev.listNodes[dir] = node;
    } else {
      _nodes[dir ^ 1] = node;
    }
  }

  void _insertNode(N ref, N node, int dir) {
    final prev = ref;
    final next = ref.listNodes[dir];

    prev.listNodes[dir] = node;
    if (next != null) {
      next.listNodes[dir ^ 1] = node;
    } else {
      _nodes[dir] = node;
    }

    node.listNodes[dir ^ 1] = prev;
    node.listNodes[dir] = next;
  }

  void append(N node) => _addNode(node, kNodeIndexLast);
  void prepend(N node) => _addNode(node, kNodeIndexFirst);

  void insertAfter(N ref, N node) =>
      _insertNode(ref, node, ArenaListNode.kNodeIndexNext);
  void insertBefore(N ref, N node) =>
      _insertNode(ref, node, ArenaListNode.kNodeIndexPrev);

  N unlink(N node) {
    final prev = node.prev;
    final next = node.next;

    if (prev != null) {
      prev.listNodes[1] = next;
    } else {
      _nodes[0] = next;
    }
    if (next != null) {
      next.listNodes[0] = prev;
    } else {
      _nodes[1] = prev;
    }

    node.listNodes[0] = null;
    node.listNodes[1] = null;
    return node;
  }

  N popFirst() {
    final node = _nodes[0]!;
    final next = node.next;
    _nodes[0] = next;

    if (next != null) {
      next.listNodes[0] = null;
      node.listNodes[1] = null;
    } else {
      _nodes[1] = null;
    }
    return node;
  }

  N pop() {
    final node = _nodes[1]!;
    final prev = node.prev;
    _nodes[1] = prev;

    if (prev != null) {
      prev.listNodes[1] = null;
      node.listNodes[0] = null;
    } else {
      _nodes[0] = null;
    }
    return node;
  }
}
