"""The .NET editorconfig template, checked by real builds of a throwaway project.

Clean code must build, each kind of violation must fail with its rule id, and
sentence-style test names stay allowed under tests/.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
REPO = Path(__file__).resolve().parent.parent
TEMPLATE = REPO / "plugins/vibe-coding/skills/vibe-coding/assets/dotnet.editorconfig"

PROPS = """<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
"""
CLEAN = """namespace Sample;

public sealed class Counter
{
    private const int Step = 1;
    private static readonly System.Threading.Lock Gate = new();
    private readonly int _start;
    private int _count;

    public Counter(int start)
    {
        _start = start;
    }

    public int Next()
    {
        lock (Gate)
        {
            _count += Step;
            return _start + _count;
        }
    }
}
"""
SENTENCE_TEST = """namespace Sample;

public static class CounterTests
{
    public static void Abgelehnte_Gastbuchung_legt_keinen_Kunden_an()
    {
    }

    public static void Given_ein_Gast_When_er_bucht_Then_steht_der_Termin()
    {
    }
}
"""
VIOLATIONS = {
    "IDE1006": """namespace Sample;
public sealed class Names
{
    private int count;
    public int Next() => count++;
}
""",
    "IDE0005": """using System.Text;

namespace Sample;
public static class Imports
{
    public static int One() => 1;
}
""",
    "IDE0051": """namespace Sample;
public static class Unused
{
    public static int One() => 1;
    private static int Two() => 2;
}
""",
    "IDE0052": """namespace Sample;
public sealed class Unread
{
    private int _value;
    public void Set(int value) => _value = value;
}
""",
    "IDE0044": """namespace Sample;
public sealed class NotReadonly
{
    private int _value = 1;
    public int Get() => _value;
}
""",
    "IDE0161": """namespace Sample
{
    public static class Block
    {
        public static int One() => 1;
    }
}
""",
    "CA5351": """using System.Security.Cryptography;

namespace Sample;
public static class Weak
{
    public static byte[] Hash(byte[] data) => MD5.HashData(data);
}
""",
    "CA2016": """using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace Sample;
public static class Cancel
{
    public static async Task WaitAsync(Stream stream, CancellationToken token) => await stream.FlushAsync();
}
""",
    "CA2213": """using System;
using System.IO;

namespace Sample;
public sealed class Owner : IDisposable
{
    private readonly FileStream _stream;
    public Owner(string path)
    {
        _stream = new FileStream(path, FileMode.Open);
    }
    public long Length => _stream.Length;
    public void Dispose()
    {
    }
}
""",
    "IDE0330": """namespace Sample;
public static class OldLock
{
    private static readonly object Gate = new();
    public static int One()
    {
        lock (Gate)
        {
            return 1;
        }
    }
}
""",
}


def dotnet_framework():
    version = subprocess.run(["dotnet", "--version"], capture_output=True, text=True, check=True).stdout
    return f"net{version.split('.')[0]}.0"


def make_project(root, files):
    framework = dotnet_framework()
    (root / "Sample.csproj").write_text(
        f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>{framework}</TargetFramework></PropertyGroup></Project>',
        encoding="utf-8",
        newline="\n",
    )
    (root / "Directory.Build.props").write_text(PROPS, encoding="utf-8", newline="\n")
    shutil.copy(TEMPLATE, root / ".editorconfig")
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")


def build(root):
    result = subprocess.run(
        ["dotnet", "build", "--nologo", "-v", "q", "-p:UseSharedCompilation=false"],
        cwd=root,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.returncode, result.stdout + result.stderr


def main():
    failures = []
    with tempfile.TemporaryDirectory() as temp:
        clean = Path(temp) / "clean"
        clean.mkdir()
        make_project(clean, {"Counter.cs": CLEAN, "tests/CounterTests.cs": SENTENCE_TEST})
        code, output = build(clean)
        print("clean project builds:", "ok" if code == 0 else "FAILED")
        if code != 0:
            failures.append("clean: " + output[-1500:])

        for rule, source in VIOLATIONS.items():
            root = Path(temp) / rule
            root.mkdir()
            make_project(root, {"Counter.cs": CLEAN, "Bad.cs": source})
            code, output = build(root)
            found = bool(re.search(rf"\b{rule}\b", output))
            print(f"{rule}:", "ok" if code != 0 and found else "FAILED")
            if code == 0 or not found:
                failures.append(f"{rule}: exit {code}\n{output[-800:]}")

    for failure in failures:
        print(failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
