FROM dart:stable
#  '"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -Command '"'"'docker run --rm --platform linux/arm64 asmjit-arm64-test:latest bash -lc "/usr/lib/dart/bin/dart test test/blend2d/pipeline_src_over_test.dart -p vm"'"'"

# Example run (from Windows/PowerShell):
# docker run --rm --platform linux/arm64 `
#   -v ${PWD}:/workspace -w /workspace `
#   -v asmjit_dart_tool_arm64:/workspace/.dart_tool `
#   -v asmjit_pub_cache_arm64:/root/.pub-cache `
#   asmjit-arm64-test:latest `
#   bash -lc "dart --version && dart pub get --no-precompile && dart test -j 1"

WORKDIR /app

# Ensure Dart is on PATH for arm64 images.
ENV PATH="/usr/lib/dart/bin:${PATH}"

# Cache pub dependencies first (copies only pubspecs).
COPY pubspec.* ./
RUN dart pub get --no-precompile

# Now copy the full source.
COPY . .

# Ensure dependencies are up to date after sources are copied.
RUN dart pub get --no-precompile

# Default command: run the full test suite.
CMD ["/usr/lib/dart/bin/dart", "test", "-j", "1", "--reporter=expanded"]
