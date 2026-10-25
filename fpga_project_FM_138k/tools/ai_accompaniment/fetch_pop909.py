"""Fetch a small, pinned POP909 subset for accompaniment research.
Raw MIDI stays in ignored tmp; manifest records individual hashes and source.
"""
import argparse
import hashlib
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REV='d83e6edba6872a704f5d3b8b32f5cb540088dae6'
BASE='https://raw.githubusercontent.com/music-x-lab/POP909-Dataset/'+REV+'/'
ROOT=Path(__file__).resolve().parents[2]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--songs',type=int,default=48);args=ap.parse_args()
    dst=ROOT/'tmp/ai_pop909';dst.mkdir(exist_ok=True)
    jobs=['LICENSE','README.md']
    for i in range(1,args.songs+1):
        folder='POP909/%03d/'%i
        jobs += [folder+'%03d.mid'%i,folder+'chord_midi.txt',folder+'beat_midi.txt']
    def get(name):
        p=dst/name;p.parent.mkdir(parents=True,exist_ok=True)
        if not p.exists():
            for attempt in range(3):
                try:
                    data=urllib.request.urlopen(BASE+name,timeout=40).read()
                    p.write_bytes(data);break
                except Exception:
                    if attempt==2:raise
                    time.sleep(1+attempt)
        return {'path':name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    with ThreadPoolExecutor(max_workers=6) as pool:files=list(pool.map(get,jobs))
    manifest={'repository':'https://github.com/music-x-lab/POP909-Dataset','revision':REV,
              'citation':'Wang et al., POP909: A Pop-song Dataset for Music Arrangement Generation, ISMIR 2020',
              'license_file':'LICENSE','files':files}
    (dst/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print('Fetched %d songs, %d files, pinned %s'%(args.songs,len(files),REV),flush=True)

if __name__=='__main__':main()
