S=/private/tmp/claude-501/-Volumes-ssd-dock-MyProjectsDart-asmjit/ac579a70-6b8a-4971-9dad-c3d5e7d3806b/scratchpad
cd /Volumes/ssd_dock/MyProjectsDart/asmjit
python3 $S/a64port/translate.py $S/a64emit.cpp $S/a64port/body.dart.txt $S/a64port/states.txt >/dev/null || exit 1
python3 $S/a64port/assemble.py || exit 1
dart analyze lib/src/asmjit/arm/a64_emit.dart 2>&1 | grep -E " error " | sed -E 's/.*a64_emit.dart:([0-9]+):([0-9]+) - (.*)/\1:\2 \3/' | sort -n > $S/a64port/errors.txt
wc -l < $S/a64port/errors.txt
