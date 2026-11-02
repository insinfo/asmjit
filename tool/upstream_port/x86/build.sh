S=/private/tmp/claude-501/-Volumes-ssd-dock-MyProjectsDart-asmjit/ac579a70-6b8a-4971-9dad-c3d5e7d3806b/scratchpad
cd /Volumes/ssd_dock/MyProjectsDart/asmjit
python3 $S/x86port/translate.py $S/emit.cpp $S/x86port/body.dart.txt $S/x86port/states.txt >/dev/null
python3 $S/x86port/assemble.py || exit 1
dart analyze lib/src/asmjit/x86/x86_emit.dart 2>&1 | grep -E " error " | sed -E 's/.*x86_emit.dart:([0-9]+):([0-9]+) - (.*)/\1:\2 \3/' | sort -n > $S/x86port/errors.txt
wc -l < $S/x86port/errors.txt
