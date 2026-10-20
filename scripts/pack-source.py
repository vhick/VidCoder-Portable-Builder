"""Archive every tracked upstream source file AFTER patching; no generated binaries."""
from pathlib import Path
import subprocess
import sys
import zipfile

root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).split(b'\x00')
count = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for item in tracked:
        if not item:
            continue
        rel = item.decode('utf-8', errors='surrogateescape')
        path = root / rel
        if path.is_file():
            z.write(path, rel)
            count += 1
for required in ('VidCoderCommon/Utilities/CommonUtilities.cs', 'VidCoder/Model/Database.cs', 'VidCoder/Utilities/Utilities.cs'):
    if required not in zipfile.ZipFile(out).namelist():
        raise SystemExit('Required modified source not included: ' + required)
print(f'Archived {count} tracked source files, including actual modified sources.')
