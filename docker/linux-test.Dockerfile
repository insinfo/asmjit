FROM dart:stable
# 
#docker run --rm -v "${PWD}:/workspace" -v "$HOME/.pub-cache:/root/.pub-cache" -w /workspace dart:stable /bin/bash -lc 'export PATH=/usr/lib/dart/bin:$PATH; dart pub get --no-precompile >/tmp/pubget.log && dart run _tmp_dump.dart'
#docker run --rm -v "${PWD}:/workspace" -v "$HOME/.pub-cache:/root/.pub-cache" -w /workspace dart:stable /bin/bash -lc 'export PATH=/usr/lib/dart/bin:$PATH; dart test -j 1'


WORKDIR /app

# Cache pub dependencies first (copies only pubspecs).
COPY pubspec.* ./
RUN dart pub get --no-precompile

# Now copy the full source.
COPY . .

# Ensure dependencies are up to date after sources are copied.
RUN dart pub get --no-precompile

# Default command: run the full test suite.
CMD ["dart", "test", "--reporter=expanded"]
