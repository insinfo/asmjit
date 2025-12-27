// Basic benchmark to compare manual lookup vs map lookup
// and general overhead of "Idiomatic" serialization.

class MockAssembler {
  int callCount = 0;
  void movRR(int a, int b) {
    callCount++;
  }

  void movRI(int a, int b) {
    callCount++;
  }

  void addRR(int a, int b) {
    callCount++;
  }
}

// 1. "Manual" Dispatch (Switch case - like Native C++ switch tables)
void manualDispatch(MockAssembler asm, int id, int a, int b) {
  switch (id) {
    case 0:
      asm.movRR(a, b);
      break;
    case 1:
      asm.movRI(a, b);
      break;
    case 2:
      asm.addRR(a, b);
      break;
    default:
      break;
  }
}

// 2. "Idiomatic" Dispatch (Map of closures)
typedef Handler = void Function(MockAssembler, int, int);
final Map<int, Handler> lookup = {
  0: (asm, a, b) => asm.movRR(a, b),
  1: (asm, a, b) => asm.movRI(a, b),
  2: (asm, a, b) => asm.addRR(a, b),
};

void idiomaticDispatch(MockAssembler asm, int id, int a, int b) {
  final h = lookup[id];
  if (h != null) h(asm, a, b);
}

// 3. "Flat" List Dispatch (List of closures - faster than Map)
final List<Handler> listLookup = List.filled(3, (asm, a, b) {});
void setupList() {
  listLookup[0] = (asm, a, b) => asm.movRR(a, b);
  listLookup[1] = (asm, a, b) => asm.movRI(a, b);
  listLookup[2] = (asm, a, b) => asm.addRR(a, b);
}

void listDispatch(MockAssembler asm, int id, int a, int b) {
  if (id < listLookup.length) {
    listLookup[id](asm, a, b);
  }
}

// 4. "If-Else" Dispatch
void ifElseDispatch(MockAssembler asm, int id, int a, int b) {
  if (id == 0) {
    asm.movRR(a, b);
  } else if (id == 1) {
    asm.movRI(a, b);
  } else if (id == 2) {
    asm.addRR(a, b);
  }
}

void main() {
  setupList();

  final asm = MockAssembler();
  final iterations = 10000000;
  final stopwatch = Stopwatch();

  print('Benchmarking Dispatch Strategies ($iterations iterations)...');

  // Warmup
  for (var i = 0; i < 1000; i++) manualDispatch(asm, 0, 1, 2);

  // 1. Manual Switch
  stopwatch.start();
  for (var i = 0; i < iterations; i++) {
    manualDispatch(asm, i % 3, 1, 2);
  }
  stopwatch.stop();
  final tManual = stopwatch.elapsedMilliseconds;
  print('Manual Switch: ${tManual}ms');

  // 2. Map
  stopwatch.reset();
  stopwatch.start();
  for (var i = 0; i < iterations; i++) {
    idiomaticDispatch(asm, i % 3, 1, 2);
  }
  stopwatch.stop();
  final tMap = stopwatch.elapsedMilliseconds;
  print('Map Lookup:    ${tMap}ms');

  // 3. List
  stopwatch.reset();
  stopwatch.start();
  for (var i = 0; i < iterations; i++) {
    listDispatch(asm, i % 3, 1, 2);
  }
  stopwatch.stop();
  final tList = stopwatch.elapsedMilliseconds;
  print('List Lookup:   ${tList}ms');

  // 4. If-Else
  stopwatch.reset();
  stopwatch.start();
  for (var i = 0; i < iterations; i++) {
    ifElseDispatch(asm, i % 3, 1, 2);
  }
  stopwatch.stop();
  final tIfElse = stopwatch.elapsedMilliseconds;
  print('If-Else:       ${tIfElse}ms');

  print('\nResults:');
  print('List is ${(tMap / tList).toStringAsFixed(2)}x faster than Map');
  print('Switch is ${(tList / tManual).toStringAsFixed(2)}x faster than List');
  print(
      'If-Else is ${(tManual / tIfElse).toStringAsFixed(2)}x faster than Switch');

  // Overhead Calculation
  // A real assembler instruction (encoding) takes roughly 10-50ns typical.
  // 10M instructions in 100ms = 10ns per dispatch.
  // If dispatch is 10ns, it is negligible compared to encoding (if encoding is heavy).
  // But if encoding is just writing 2 bytes (light), dispatch matters.
}
