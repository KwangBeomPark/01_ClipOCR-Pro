[CmdletBinding()]
param(
    [string]$TargetDirectory = "",
    [string]$PythonPath = "",
    [string]$ModelsSourceDirectory = "",
    [switch]$IncludeLatinModel,
    [switch]$SkipSelfTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
    $TargetDirectory = Join-Path $repoRoot "tools\rapidocr"
}
$resolvedTarget = [IO.Path]::GetFullPath($TargetDirectory)
$resolvedRepoRoot = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\')

if ($resolvedTarget.TrimEnd('\') -ieq $resolvedRepoRoot) {
    throw "TargetDirectory must not be the repository root itself: $resolvedTarget"
}
foreach ($protectedFolder in @("src", "scripts", "tests", "docs", "installer", "assets", ".github", ".git")) {
    $protectedPath = (Join-Path $resolvedRepoRoot $protectedFolder).TrimEnd('\')
    if ($resolvedTarget.TrimEnd('\') -ieq $protectedPath -or
        $resolvedTarget.StartsWith(($protectedPath + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "TargetDirectory must not point inside tracked repository folder '$protectedFolder': $resolvedTarget"
    }
}

function Assert-NoReparsePoint {
    param(
        [string]$Path,
        [string]$Description = "Target path"
    )

    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $probe = $full
    while (-not [string]::IsNullOrWhiteSpace($probe)) {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "$Description cannot traverse or target a symlink or junction: $probe"
            }
        }
        $parent = Split-Path -Parent $probe
        if ($parent -eq $probe) {
            break
        }
        $probe = $parent
    }
}

Assert-NoReparsePoint $resolvedTarget "TargetDirectory"

$venvDir = Join-Path $resolvedTarget ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"
$modelsDir = Join-Path $resolvedTarget "models"
foreach ($subPath in @($venvDir, (Join-Path $venvDir "pyvenv.cfg"), (Join-Path $venvDir "Scripts"), $venvPython, (Join-Path $venvDir "Lib"), (Join-Path $venvDir "Lib\site-packages"), $modelsDir)) {
    Assert-NoReparsePoint $subPath "RapidOCR writable path"
}

function Invoke-QuietProcess {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )

    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $Executable @Arguments 2>&1 | ForEach-Object { ([string]$_).TrimEnd() })
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    } finally {
        $ErrorActionPreference = $prevPref
    }
}

function Test-SupportedPython {
    param(
        [string]$ExecutablePath,
        [switch]$RequireVenv
    )

    if ([string]::IsNullOrWhiteSpace($ExecutablePath) -or -not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        return $false
    }
    $modules = if ($RequireVenv) { "struct, sys, venv" } else { "struct, sys" }
    try {
        $probe = Invoke-QuietProcess $ExecutablePath @("-I", "-c", "import $modules; raise SystemExit(0 if (sys.version_info >= (3, 11) and struct.calcsize('P') * 8 == 64) else 1)")
        return ($probe.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Resolve-PythonExecutable {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $fullRequested = [IO.Path]::GetFullPath($RequestedPath)
        if (-not (Test-SupportedPython $fullRequested -RequireVenv)) {
            throw "Requested Python executable is invalid (requires 64-bit Python 3.11+ with venv): $fullRequested"
        }
        return $fullRequested
    }

    $candidates = [Collections.Generic.List[string]]::new()
    $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
    if ($null -ne $pyCmd -and -not [string]::IsNullOrWhiteSpace($pyCmd.Source)) {
        $candidates.Add($pyCmd.Source)
    }
    $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
    if ($null -ne $pyLauncher) {
        foreach ($pyTag in @("-3", "-3.13", "-3.12", "-3.11")) {
            try {
                $pyRes = Invoke-QuietProcess $pyLauncher.Source @($pyTag, "-c", "import sys; print(sys.executable)")
                if ($pyRes.ExitCode -eq 0 -and $pyRes.Output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($pyRes.Output[-1])) {
                    $candidates.Add($pyRes.Output[-1].Trim())
                }
            } catch {
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        foreach ($verDir in @("Python313", "Python312", "Python311")) {
            $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Python\$verDir\python.exe"))
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-SupportedPython $candidate -RequireVenv) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw "No supported 64-bit Python 3.11+ installation (with venv module) was found. Pass -PythonPath explicitly."
}

$basePython = Resolve-PythonExecutable -RequestedPath $PythonPath
Write-Host "Using Python: $basePython"

if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedTarget -Force | Out-Null
}
Assert-NoReparsePoint $resolvedTarget "TargetDirectory"

if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
    Assert-NoReparsePoint $venvPython "Existing virtual environment Python"
    if (-not (Test-SupportedPython $venvPython)) {
        throw "Existing virtual environment at $venvDir is not 64-bit Python 3.11+. Remove $venvDir and rerun."
    }
} else {
    Assert-NoReparsePoint $venvDir "Virtual environment directory"
    Write-Host "Creating isolated virtual environment at $venvDir..."
    $venvRes = Invoke-QuietProcess $basePython @("-m", "venv", $venvDir)
    if ($venvRes.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        throw "Failed to create Python virtual environment at ${venvDir}: $($venvRes.Output -join ' ')"
    }
    Assert-NoReparsePoint $venvPython "Created virtual environment Python"
}

function Invoke-TempPythonScript {
    param(
        [string]$PythonExe,
        [string]$ScriptBody,
        [string[]]$Arguments = @()
    )

    $tmpScript = Join-Path $env:TEMP ("clipocr_setup_" + [guid]::NewGuid().ToString("N") + ".py")
    try {
        [IO.File]::WriteAllText($tmpScript, $ScriptBody, [Text.UTF8Encoding]::new($false))
        $allArgs = @("-I", "-X", "utf8", $tmpScript) + $Arguments
        return Invoke-QuietProcess $PythonExe $allArgs
    } finally {
        Remove-Item -LiteralPath $tmpScript -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-IsolatedVenvPip {
    param(
        [string]$VenvPythonExe,
        [string]$VenvRoot,
        [string[]]$PipArguments
    )

    $savedEnv = @{}
    foreach ($entry in (Get-ChildItem Env:)) {
        if ($entry.Name -match '^(?i)(PIP_|PYTHON)' -or $entry.Name -ieq 'VIRTUAL_ENV') {
            $savedEnv[$entry.Name] = $entry.Value
            [Environment]::SetEnvironmentVariable($entry.Name, $null, "Process")
        }
    }
    foreach ($name in @("VIRTUAL_ENV", "PYTHONNOUSERSITE", "PIP_CONFIG_FILE")) {
        if (-not $savedEnv.ContainsKey($name)) {
            $savedEnv[$name] = $null
        }
    }
    [Environment]::SetEnvironmentVariable("VIRTUAL_ENV", $VenvRoot, "Process")
    [Environment]::SetEnvironmentVariable("PYTHONNOUSERSITE", "1", "Process")
    [Environment]::SetEnvironmentVariable("PIP_CONFIG_FILE", "NUL", "Process")
    try {
        $allArgs = @("-I", "-m", "pip") + $PipArguments
        return Invoke-QuietProcess $VenvPythonExe $allArgs
    } finally {
        foreach ($name in $savedEnv.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], "Process")
        }
    }
}

$venvPrefixPy = @'
import sys
from pathlib import Path

venv_root = Path(sys.argv[1]).resolve()
prefix = Path(sys.prefix).resolve()
base_prefix = Path(sys.base_prefix).resolve()
assert prefix == venv_root, f"sys.prefix={prefix} != {venv_root}"
assert prefix != base_prefix, f"sys.prefix matches sys.base_prefix={base_prefix}"
'@

$prefixProbe = Invoke-TempPythonScript $venvPython $venvPrefixPy @($venvDir)
if ($prefixProbe.ExitCode -ne 0) {
    throw "Virtual environment isolation check failed: $($prefixProbe.Output)"
}

$pkgVerifyPy = @'
import importlib.metadata as m
import sys
from pathlib import Path
import rapidocr
import onnxruntime

venv_root = Path(sys.argv[1]).resolve()
assert m.version("rapidocr") == "3.10.0", f"rapidocr={m.version('rapidocr')}"
assert m.version("onnxruntime") == "1.32.0", f"onnxruntime={m.version('onnxruntime')}"
for mod in (rapidocr, onnxruntime):
    Path(mod.__file__).resolve().relative_to(venv_root)
'@

$pkgProbe = Invoke-TempPythonScript $venvPython $pkgVerifyPy @($venvDir)
if ($pkgProbe.ExitCode -ne 0) {
    Assert-NoReparsePoint (Join-Path $venvDir "Lib\site-packages") "Virtual environment site-packages"
    Write-Host "Installing rapidocr==3.10.0 and onnxruntime==1.32.0 into $venvDir..."
    $pipRes = Invoke-IsolatedVenvPip $venvPython $venvDir @("install", "--isolated", "--no-user", "rapidocr==3.10.0", "onnxruntime==1.32.0")
    if ($pipRes.ExitCode -ne 0) {
        throw "Failed to install rapidocr==3.10.0 and onnxruntime==1.32.0 inside ${venvDir}: $($pipRes.Output -join ' ')"
    }
    $pkgVerifyAfter = Invoke-TempPythonScript $venvPython $pkgVerifyPy @($venvDir)
    if ($pkgVerifyAfter.ExitCode -ne 0) {
        throw "Installed RapidOCR/ONNXRuntime verification failed inside ${venvDir}: $($pkgVerifyAfter.Output -join ' ')"
    }
}

if (-not (Test-Path -LiteralPath $modelsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $modelsDir -Force | Out-Null
}
Assert-NoReparsePoint $modelsDir "Models directory"

$requiredModels = @(
    @{ Name = "ch_PP-OCRv5_det_mobile.onnx"; Kind = "det"; Key = "ch_PP-OCRv5_det_mobile" },
    @{ Name = "korean_PP-OCRv5_rec_mobile.onnx"; Kind = "rec"; Key = "korean_PP-OCRv5_rec_mobile" }
)
if ($IncludeLatinModel) {
    $requiredModels += @{ Name = "latin_PP-OCRv5_rec_mobile.onnx"; Kind = "rec"; Key = "latin_PP-OCRv5_rec_mobile" }
}
foreach ($model in $requiredModels) {
    Assert-NoReparsePoint (Join-Path $modelsDir $model.Name) "Model file destination"
}

$sourceModelsDir = ""
if (-not [string]::IsNullOrWhiteSpace($ModelsSourceDirectory)) {
    $sourceModelsDir = [IO.Path]::GetFullPath($ModelsSourceDirectory)
    if (-not (Test-Path -LiteralPath $sourceModelsDir -PathType Container)) {
        throw "ModelsSourceDirectory was not found: $sourceModelsDir"
    }
}

$stagePy = @'
import logging, os, shutil, sys, yaml, rapidocr
from rapidocr.utils.download_file import DownloadFile, DownloadFileInput

models_dir, source_dir_arg, kind, key, filename = sys.argv[1:6]
source_dir = "" if source_dir_arg == "-" else source_dir_arg
cfg_path = os.path.join(os.path.dirname(rapidocr.__file__), "default_models.yaml")
with open(cfg_path, encoding="utf-8") as f:
    meta = yaml.safe_load(f)["onnxruntime"]["PP-OCRv5"][kind][key]
expected_sha = meta["SHA256"]
dst = os.path.join(models_dir, filename)
pkg_cache = os.path.join(os.path.dirname(rapidocr.__file__), "models", filename)

def is_valid(path):
    return os.path.isfile(path) and os.path.getsize(path) > 0 and DownloadFile.check_file_sha256(path, expected_sha)

if not is_valid(dst):
    copied = False
    for cand_dir in [source_dir, os.path.dirname(pkg_cache)]:
        if not cand_dir:
            continue
        cand = os.path.join(cand_dir, filename)
        if is_valid(cand):
            shutil.copyfile(cand, dst)
            copied = True
            break
    if not copied:
        logger = logging.getLogger("clipocr_setup")
        DownloadFile.run(DownloadFileInput(
            file_url=meta["model_dir"],
            save_path=dst,
            logger=logger,
            sha256=expected_sha,
        ))
    if not is_valid(dst):
        raise RuntimeError(f"Checksum verification failed for {dst}")
print(f"READY:{filename}:{os.path.getsize(dst)}")
'@

$sourceModelsArg = if ([string]::IsNullOrWhiteSpace($sourceModelsDir)) { "-" } else { $sourceModelsDir }
foreach ($model in $requiredModels) {
    $stageRes = Invoke-TempPythonScript $venvPython $stagePy @($modelsDir, $sourceModelsArg, $model.Kind, $model.Key, $model.Name)
    if ($stageRes.ExitCode -ne 0) {
        throw "Failed to prepare model $($model.Name): $($stageRes.Output -join ' ')"
    }
    Write-Host ($stageRes.Output -join "`n")
}

if (-not $SkipSelfTest) {
    $runnerPath = Join-Path $repoRoot "scripts\Invoke-RapidOcr.py"
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
        throw "Invoke-RapidOcr.py was not found: $runnerPath"
    }
    $makeKoSamplePy = @'
import os, sys
from PIL import Image, ImageDraw, ImageFont

out_img = sys.argv[1]
fonts_dir = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
font_path = next((os.path.join(fonts_dir, name) for name in ("malgun.ttf", "gulim.ttc", "batang.ttc") if os.path.isfile(os.path.join(fonts_dir, name))), None)
if not font_path:
    raise RuntimeError("No Korean Windows font (malgun.ttf, gulim.ttc, batang.ttc) is available for RapidOCR self-test.")

img = Image.new("RGB", (360, 72), (255, 255, 255))
draw = ImageDraw.Draw(img)
font = ImageFont.truetype(font_path, 22)
draw.text((20, 20), "\ud14c\uc2a4\ud2b8 \uc2a4\ub9c8\ud2b8 \ub178\ud2b8 E\ud2b8", fill=(0, 0, 0), font=font)
img.save(out_img)
'@
    $tempId = [guid]::NewGuid().ToString("N")
    $testImg = Join-Path $env:TEMP "clipocr_rapid_img_$tempId.png"
    $testOut = Join-Path $env:TEMP "clipocr_rapid_out_$tempId.txt"
    $testStatus = Join-Path $env:TEMP "clipocr_rapid_status_$tempId.status"
    try {
        $sampleRes = Invoke-TempPythonScript $venvPython $makeKoSamplePy @($testImg)
        if ($sampleRes.ExitCode -ne 0) {
            throw "Could not generate RapidOCR Korean self-test image: $($sampleRes.Output -join ' ')"
        }
        $runRes = Invoke-QuietProcess $venvPython @("-I", "-X", "utf8", $runnerPath, "--image", $testImg, "--lang", "ko-KR", "--models-dir", $modelsDir, "--output", $testOut, "--status", $testStatus)
        $statusLine = if (Test-Path -LiteralPath $testStatus -PathType Leaf) { ([IO.File]::ReadAllText($testStatus, [Text.UTF8Encoding]::new($false))).Trim() } else { "" }
        $ocrText = if (Test-Path -LiteralPath $testOut -PathType Leaf) { ([IO.File]::ReadAllText($testOut, [Text.UTF8Encoding]::new($false))).Trim() } else { "" }
        $expectedSmart = -join @([char]0xC2A4, [char]0xB9C8, [char]0xD2B8)
        $expectedETeu = "E" + [char]0xD2B8
        if ($runRes.ExitCode -ne 0 -or -not $statusLine.StartsWith("OK|ko|") -or -not $ocrText.Contains($expectedSmart) -or -not $ocrText.Contains($expectedETeu)) {
            throw "RapidOCR Korean self-test failed (exit=$($runRes.ExitCode), status='$statusLine', text='$ocrText', out='$($runRes.Output -join ' ')')."
        }
        Write-Host "RapidOCR offline Korean self-test PASS ($statusLine): $ocrText"
    } finally {
        Remove-Item -LiteralPath $testImg, $testOut, $testStatus -Force -ErrorAction SilentlyContinue
    }

    if ($IncludeLatinModel) {
        $makeLaSamplePy = @'
import os, sys
from PIL import Image, ImageDraw, ImageFont

out_img = sys.argv[1]
fonts_dir = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
font_path = next((os.path.join(fonts_dir, name) for name in ("segoeui.ttf", "arial.ttf", "calibri.ttf") if os.path.isfile(os.path.join(fonts_dir, name))), None)
if not font_path:
    raise RuntimeError("No Latin Windows font (segoeui.ttf, arial.ttf, calibri.ttf) is available for RapidOCR Latin self-test.")

img = Image.new("RGB", (360, 72), (255, 255, 255))
draw = ImageDraw.Draw(img)
font = ImageFont.truetype(font_path, 22)
draw.text((20, 20), "Faktura VAT 2026 PL", fill=(0, 0, 0), font=font)
img.save(out_img)
'@
        $latId = [guid]::NewGuid().ToString("N")
        $latImg = Join-Path $env:TEMP "clipocr_rapid_la_img_$latId.png"
        $latOut = Join-Path $env:TEMP "clipocr_rapid_la_out_$latId.txt"
        $latStatus = Join-Path $env:TEMP "clipocr_rapid_la_status_$latId.status"
        try {
            $latSampleRes = Invoke-TempPythonScript $venvPython $makeLaSamplePy @($latImg)
            if ($latSampleRes.ExitCode -ne 0) {
                throw "Could not generate RapidOCR Latin self-test image: $($latSampleRes.Output -join ' ')"
            }
            $latRunRes = Invoke-QuietProcess $venvPython @("-I", "-X", "utf8", $runnerPath, "--image", $latImg, "--lang", "pl-PL", "--models-dir", $modelsDir, "--output", $latOut, "--status", $latStatus)
            $latStatusLine = if (Test-Path -LiteralPath $latStatus -PathType Leaf) { ([IO.File]::ReadAllText($latStatus, [Text.UTF8Encoding]::new($false))).Trim() } else { "" }
            $latOcrText = if (Test-Path -LiteralPath $latOut -PathType Leaf) { ([IO.File]::ReadAllText($latOut, [Text.UTF8Encoding]::new($false))).Trim() } else { "" }
            if ($latRunRes.ExitCode -ne 0 -or -not $latStatusLine.StartsWith("OK|pl|") -or -not $latOcrText.Contains("Faktura") -or -not $latOcrText.Contains("VAT")) {
                throw "RapidOCR Latin self-test failed (exit=$($latRunRes.ExitCode), status='$latStatusLine', text='$latOcrText', out='$($latRunRes.Output -join ' ')')."
            }
            Write-Host "RapidOCR offline Latin self-test PASS ($latStatusLine): $latOcrText"
        } finally {
            Remove-Item -LiteralPath $latImg, $latOut, $latStatus -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "RapidOCR runtime ready at: $resolvedTarget"
