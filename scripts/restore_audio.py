"""Restore the separately supplied audio pack after verifying all expected bytes."""
from pathlib import Path
import argparse,hashlib,json,zipfile

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    files=json.loads((root/'audio-manifest.json').read_text(encoding='utf-8'))['files']
    pending=[]
    with zipfile.ZipFile(args.archive) as archive:
        for row in files:
            relative=Path(row['path'])
            if relative.is_absolute() or '..' in relative.parts or relative.parts[:3]!=('frontend','assets','sounds'):
                raise ValueError('Unexpected manifest target')
            target=(root/relative).resolve()
            if not target.is_relative_to(root/'frontend/assets/sounds'):
                raise ValueError('Target outside audio directory')
            info=archive.getinfo(row['path'])
            if info.file_size!=row['bytes']:raise ValueError('Audio size mismatch: '+row['path'])
            data=archive.read(info)
            if hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('Audio hash mismatch: '+row['path'])
            pending.append((target,data))
    # Verify the entire pack before writing any output. No arbitrary extraction.
    for target,data in pending:
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    print(f'Restored {len(pending)} verified original audio files.')

if __name__=='__main__':main()
