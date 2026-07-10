import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  int? parseIntArg(String? s) => s == null ? null : int.tryParse(s);

  String? procdumpPath;
  String dumpDir = 'tool/repro_dumps';
  bool enableDump = true;
  bool firstChance = true;

  final positional = <String>[];
  for (final a in args) {
    if (a.startsWith('--procdump=')) {
      procdumpPath = a.substring('--procdump='.length).trim();
    } else if (a.startsWith('--dumpDir=')) {
      dumpDir = a.substring('--dumpDir='.length).trim();
    } else if (a == '--no-dump') {
      enableDump = false;
    } else if (a == '--unhandled-only') {
      firstChance = false;
    } else {
      positional.add(a);
    }
  }

  final iterations =
      positional.isNotEmpty ? parseIntArg(positional[0]) ?? 200 : 200;
  final concurrency =
      positional.length >= 2 ? parseIntArg(positional[1]) ?? 1 : 1;

  final testPath = r'test/problema/integration_abi_test.dart';
  final dartExe = Platform.resolvedExecutable;

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final outDir = Directory('tool/repro_logs');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final runLogPath = 'tool/repro_logs/abi_repro_$timestamp.log';
  final runLog = File(runLogPath);

  Future<void> append(String s) async {
    await runLog.writeAsString(s, mode: FileMode.append, flush: true);
  }

  await append('dartExe=$dartExe\n');
  await append('iterations=$iterations concurrency=$concurrency\n');
  await append('test=$testPath\n\n');

  String? resolveProcDump() {
    if (!enableDump) return null;
    final candidates = <String>[];
    final procdump = procdumpPath;
    if (procdump != null && procdump.isNotEmpty) {
      candidates.add(procdump);
    }
    candidates.addAll([
      r'C:\SysinternalsSuite\procdump64.exe',
      r'C:\SysinternalsSuite\procdump.exe',
      r'C:\tools\procdump64.exe',
      r'C:\tools\procdump.exe',
      'procdump64.exe',
      'procdump.exe',
    ]);
    for (final c in candidates) {
      try {
        if (c.contains('\\') || c.contains(':')) {
          if (File(c).existsSync()) return c;
        } else {
          // If it's in PATH, Process.start will resolve it.
          return c;
        }
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

  final resolvedProcDump = resolveProcDump();
  if (enableDump && resolvedProcDump == null) {
    await append(
        'WARN: ProcDump not found; continuing without dumps. Use --procdump=PATH\n');
  } else {
    await append('procdump=${resolvedProcDump ?? '(disabled)'}\n');
    await append('dumpDir=$dumpDir firstChance=$firstChance\n\n');
  }

  final dumpDirObj = Directory(dumpDir);
  if (enableDump) {
    dumpDirObj.createSync(recursive: true);
  }

  Set<String> snapshotDumpFiles() {
    try {
      if (!dumpDirObj.existsSync()) return <String>{};
      return dumpDirObj
          .listSync(followLinks: false)
          .whereType<File>()
          .map((f) => f.path)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<int?> startProcDumpForPid(int pid) async {
    if (!enableDump || resolvedProcDump == null) return null;
    final before = snapshotDumpFiles();

    final procdumpArgs = <String>[
      '-accepteula',
      '-ma',
      if (firstChance) ...['-e', '1'] else '-e',
      '-x',
      dumpDir,
      pid.toString(),
    ];

    try {
      final pd = await Process.start(
        resolvedProcDump,
        procdumpArgs,
        runInShell: true,
        mode: ProcessStartMode.normal,
      );

      // When the test exits normally, ProcDump might still be running briefly.
      unawaited(pd.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
        try {
          pd.kill(ProcessSignal.sigterm);
        } catch (_) {}
        return 0;
      }));

      // Return hash of snapshot size to help correlate.
      await append(
          'procdump(pid=$pid) started: $resolvedProcDump ${procdumpArgs.join(' ')}\n');
      // Stash snapshot in log only on failure (computed later).
      // Return 1 to indicate enabled.
      return before.length;
    } catch (e) {
      await append('WARN: failed to start procdump for pid=$pid: $e\n');
      return null;
    }
  }

  for (var i = 1; i <= iterations; i++) {
    stdout.writeln('Run $i/$iterations');

    final dumpBefore = enableDump ? snapshotDumpFiles() : <String>{};

    final proc = await Process.start(
      dartExe,
      ['test', '--concurrency=$concurrency', testPath],
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    await startProcDumpForPid(proc.pid);

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();

    final sub1 = proc.stdout
        .transform(utf8.decoder)
        .listen((chunk) => stdoutBuf.write(chunk));
    final sub2 = proc.stderr
        .transform(utf8.decoder)
        .listen((chunk) => stderrBuf.write(chunk));

    final exitCode = await proc.exitCode;
    await sub1.cancel();
    await sub2.cancel();

    final out = stdoutBuf.toString();
    final err = stderrBuf.toString();

    final combined = out + (err.isEmpty ? '' : '\n[stderr]\n$err');
    final hasCrash = combined.contains('===== CRASH =====');

    final dumpAfter = enableDump ? snapshotDumpFiles() : <String>{};
    final newDumps = dumpAfter.difference(dumpBefore).toList()..sort();

    if (exitCode != 0 || hasCrash) {
      final failPath = 'tool/repro_logs/abi_repro_FAIL_run_${i}_$timestamp.txt';
      await File(failPath).writeAsString(combined);

      await append('FAIL on run $i exitCode=$exitCode crashSig=$hasCrash\n');
      await append('Saved: $failPath\n');
      if (newDumps.isNotEmpty) {
        await append('New dumps (${newDumps.length}):\n');
        for (final p in newDumps) {
          await append('  $p\n');
        }
      } else if (enableDump) {
        await append('No new dump files detected in $dumpDir\n');
      }

      stderr.writeln('FAILED on run $i (exit=$exitCode crashSig=$hasCrash)');
      stderr.writeln('Saved output to: $failPath');
      if (newDumps.isNotEmpty) {
        stderr.writeln('New dumps:');
        for (final p in newDumps) {
          stderr.writeln('  $p');
        }
      } else if (enableDump) {
        stderr.writeln('No new dump files detected in: $dumpDir');
      }
      stderr.writeln('Run log: $runLogPath');
      exit(1);
    }

    // Light heartbeat every 10 runs.
    if (i % 10 == 0) {
      await append('ok up to run $i\n');
    }
  }

  await append('\nOK: no failures in $iterations runs\n');
  stdout.writeln('OK: no failures in $iterations runs');
  stdout.writeln('Run log: $runLogPath');
}
