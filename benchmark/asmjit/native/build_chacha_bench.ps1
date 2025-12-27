param(
  [string]$OutDir = ".",
  [string]$OutName = "chacha20_bench"
)

$ErrorActionPreference = "Stop"

$src = Join-Path $PSScriptRoot "chacha20_bench.c"
$outPath = Join-Path $OutDir "$OutName.dll"

function Invoke-Tool($exe, $toolArgs) {
  Write-Host "Running: $exe $toolArgs"
  & $exe @toolArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
  }
}

$clang = "C:\LLVM\bin\clang.exe"
$gcc = "C:\gcc\bin\gcc.exe"
$cl = "C:\Progra~1\MICROS~4\2022\Community\VC\Tools\MSVC\14.41.34120\bin\Hostx64\x64\cl.exe"
$vcvars = "C:\Progra~1\MICROS~4\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

if (Test-Path $clang) {
  try {
    Invoke-Tool $clang @("-O3", "-shared", "-fuse-ld=lld", "-o", $outPath, $src)
    exit 0
  } catch {
    Write-Host "Clang failed, trying next tool..."
  }
}

if (Test-Path $gcc) {
  try {
    Invoke-Tool $gcc @("-O3", "-shared", "-o", $outPath, $src)
    exit 0
  } catch {
    Write-Host "GCC failed, trying next tool..."
  }
}

if ((Test-Path $cl) -and (Test-Path $vcvars)) {
  $cmd = "`"$vcvars`" && `"$cl`" /O2 /LD /Fe$outPath `"$src`""
  Write-Host "Running: cmd /c $cmd"
  cmd /c $cmd
  if ($LASTEXITCODE -ne 0) {
    throw "MSVC build failed with exit code $LASTEXITCODE"
  }
  exit 0
}

throw "No working compiler found. Install LLVM/Clang, MinGW GCC, or MSVC and try again."
