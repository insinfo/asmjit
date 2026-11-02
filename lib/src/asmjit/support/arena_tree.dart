/// RB-Tree used by `JitAllocator`.
///
/// Ported from asmjit/support/arenatree.h (`ArenaTreeNode`, `ArenaTree`).
///
/// Upstream stores the color in the least significant bit of the left child
/// pointer; the Dart port keeps it in a separate field. Nodes are compared
/// with a comparator passed to the tree (upstream uses `operator<` and
/// `operator>` of the node through `Support::Compare`), which must return a
/// negative value, zero or a positive value.
library;

/// RB-Tree node (`ArenaTreeNode`).
class ArenaTreeNode {
  /// Children (`_tree_nodes[0]` is left, `_tree_nodes[1]` is right).
  final List<ArenaTreeNode?> _treeNodes = List<ArenaTreeNode?>.filled(2, null);

  /// Color (upstream `kRedMask` bit of `_tree_nodes[0]`).
  bool _red = false;

  /// Tests whether the node is red.
  bool get isRed => _red;

  /// Tests whether the node has a child `i`.
  bool hasChild(int i) => _treeNodes[i] != null;

  /// Tests whether the node has a left child.
  bool get hasLeft => _treeNodes[0] != null;

  /// Tests whether the node has a right child.
  bool get hasRight => _treeNodes[1] != null;

  /// Returns the child `i`.
  ArenaTreeNode? child(int i) => _treeNodes[i];

  /// Returns the left child.
  ArenaTreeNode? get left => _treeNodes[0];

  /// Returns the right child.
  ArenaTreeNode? get right => _treeNodes[1];

  void _setChild(int i, ArenaTreeNode? node) => _treeNodes[i] = node;

  void _makeRed() => _red = true;
  void _makeBlack() => _red = false;

  /// Clears the links and the color (a node removed from a tree).
  ///
  /// Upstream nodes are constructed (or reconstructed) with zeroed links;
  /// this is the equivalent for a node object that is reused.
  void resetTreeNode() {
    _treeNodes[0] = null;
    _treeNodes[1] = null;
    _red = false;
  }

  /// Tests whether the node is RED (RED node must be non-null and must have
  /// RED flag set).
  static bool _isValidRed(ArenaTreeNode? node) => node != null && node._red;
}

/// RB-Tree (`ArenaTree<NodeT>`).
class ArenaTree<N extends ArenaTreeNode> {
  /// Compares two nodes (`Support::Compare<kAscending>` of `NodeT`).
  final int Function(N a, N b) _cmp;

  N? _root;

  ArenaTree(this._cmp);

  /// Resets the tree (doesn't touch the nodes).
  void reset() => _root = null;

  /// Tests whether the tree is empty.
  bool get isEmpty => _root == null;

  /// Returns the root node.
  N? get root => _root;

  /// Inserts `node` into the tree.
  void insert(N node) {
    // Node to insert must not contain garbage.
    assert(!node.hasLeft);
    assert(!node.hasRight);
    assert(!node.isRed);

    if (_root == null) {
      _root = node;
      return;
    }

    final head = ArenaTreeNode(); // False root node,
    head._setChild(1, _root); //     having root on the right.

    ArenaTreeNode? g; // Grandparent.
    ArenaTreeNode? p; // Parent.
    ArenaTreeNode t = head; // Iterator.
    ArenaTreeNode? q = _root; // Query.

    var dir = 0; // Direction for accessing child nodes.
    var last = 0; // Not needed to initialize, but makes some tools happy.

    node._makeRed(); // New nodes are always red and violations fixed.

    // Search down the tree.
    for (;;) {
      if (q == null) {
        // Insert new node at the bottom.
        q = node;
        p!._setChild(dir, node);
      } else if (ArenaTreeNode._isValidRed(q.left) &&
          ArenaTreeNode._isValidRed(q.right)) {
        // Color flip.
        q._makeRed();
        q.left!._makeBlack();
        q.right!._makeBlack();
      }

      // Fix red violation.
      if (ArenaTreeNode._isValidRed(q) && ArenaTreeNode._isValidRed(p)) {
        t._setChild(
          identical(t.right, g) ? 1 : 0,
          identical(q, p!.child(last))
              ? _singleRotate(g!, last ^ 1)
              : _doubleRotate(g!, last ^ 1),
        );
      }

      // Stop if found.
      if (identical(q, node)) break;

      last = dir;
      dir = _cmp(q as N, node) < 0 ? 1 : 0;

      // Update helpers.
      if (g != null) t = g;

      g = p;
      p = q;
      q = q.child(dir);
    }

    // Update root and make it black.
    _root = head.right as N;
    _root!._makeBlack();
  }

  /// Removes `node` from the tree.
  void remove(N node) {
    final head = ArenaTreeNode(); // False root node,
    head._setChild(1, _root); //     having root on the right.

    ArenaTreeNode? g; // Grandparent.
    ArenaTreeNode? p; // Parent.
    ArenaTreeNode q = head; // Query.

    ArenaTreeNode? f; // Found item.
    ArenaTreeNode? gf; // Found grandparent.
    var dir = 1; // Direction (0 or 1).

    // Search and push a red down.
    while (q.hasChild(dir)) {
      final last = dir;

      // Update helpers.
      g = p;
      p = q;
      q = q.child(dir)!;
      dir = _cmp(q as N, node) < 0 ? 1 : 0;

      // Save found node.
      if (identical(q, node)) {
        f = q;
        gf = g;
      }

      // Push the red node down.
      if (!ArenaTreeNode._isValidRed(q) &&
          !ArenaTreeNode._isValidRed(q.child(dir))) {
        if (ArenaTreeNode._isValidRed(q.child(dir ^ 1))) {
          final child = _singleRotate(q, dir);
          p._setChild(last, child);
          p = child;
        } else if (!ArenaTreeNode._isValidRed(q.child(dir ^ 1)) &&
            p.child(last ^ 1) != null) {
          final s = p.child(last ^ 1)!;
          if (!ArenaTreeNode._isValidRed(s.child(last ^ 1)) &&
              !ArenaTreeNode._isValidRed(s.child(last))) {
            // Color flip.
            p._makeBlack();
            s._makeRed();
            q._makeRed();
          } else {
            final dir2 = identical(g!.right, p) ? 1 : 0;
            var child = g.child(dir2)!;

            if (ArenaTreeNode._isValidRed(s.child(last))) {
              child = _doubleRotate(p, last);
              g._setChild(dir2, child);
            } else if (ArenaTreeNode._isValidRed(s.child(last ^ 1))) {
              child = _singleRotate(p, last);
              g._setChild(dir2, child);
            }

            // Ensure correct coloring.
            q._makeRed();
            child._makeRed();
            child.left!._makeBlack();
            child.right!._makeBlack();
          }
        }
      }
    }

    // Replace and remove.
    assert(f != null);
    assert(!identical(f, head));
    assert(!identical(q, head));

    p!._setChild(
        identical(p.right, q) ? 1 : 0, q.child(q.left == null ? 1 : 0));

    // NOTE: The original algorithm used a trick to just copy 'key/value' to
    // `f` and mark `q` for deletion. But this is unacceptable here as we
    // really want to destroy the passed `node`. So, we have to make sure that
    // we have really removed `f` and not `q`.
    if (!identical(f, q)) {
      assert(!identical(f, head));
      assert(!identical(f, gf));

      var n = gf ?? head;
      dir = identical(n, head) ? 1 : (_cmp(n as N, node) < 0 ? 1 : 0);

      for (;;) {
        if (identical(n.child(dir), f)) {
          n._setChild(dir, q);
          // RAW copy, including the color.
          q._treeNodes[0] = f!._treeNodes[0];
          q._treeNodes[1] = f._treeNodes[1];
          q._red = f._red;
          break;
        }

        n = n.child(dir)!;

        // Cannot be null as we know that it must reach `f` in few iterations.
        dir = _cmp(n as N, node) < 0 ? 1 : 0;
      }
    }

    // Update root and make it black.
    _root = head.right as N?;
    _root?._makeBlack();
  }

  /// Returns the node matching `key` (`cmp(node, key) == 0`), or null.
  N? get<K>(K key, int Function(N node, K key) cmp) {
    ArenaTreeNode? node = _root;
    while (node != null) {
      final result = cmp(node as N, key);
      if (result == 0) break;

      // Go left or right depending on the `result`.
      node = node.child(result < 0 ? 1 : 0);
    }
    return node as N?;
  }

  /// Single rotation.
  static ArenaTreeNode _singleRotate(ArenaTreeNode root, int dir) {
    final save = root.child(dir ^ 1)!;
    final saveChild = save.child(dir);
    root._setChild(dir ^ 1, saveChild);
    save._setChild(dir, root);
    root._makeRed();
    save._makeBlack();
    return save;
  }

  /// Double rotation.
  static ArenaTreeNode _doubleRotate(ArenaTreeNode root, int dir) {
    final child = root.child(dir ^ 1)!;
    root._setChild(dir ^ 1, _singleRotate(child, dir ^ 1));
    return _singleRotate(root, dir);
  }
}
