# Runs the test suite in a Linux (amd64) Dart container.
# Requires Docker Desktop.

$platform = "linux/amd64"
$image = "dart:stable"
$project = "${PWD}"

# Mount pub cache to avoid re-downloading on every run.
$pubCache = "${HOME}/.pub-cache"

docker run --rm `
  --platform $platform `
  -v "${project}:/app" `
  -v "${pubCache}:/root/.pub-cache" `
  -w /app `
  $image `
  bash -lc "export PATH=/usr/lib/dart/bin:`$PATH; dart pub get --no-precompile && dart test --reporter=expanded"
