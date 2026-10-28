"""Resumable bounded HTTP range download; verify size and every ZIP CRC.

The data remains in tmp, outside Git. No archive member is extracted to disk.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import time
import urllib.request
import zipfile


def download(url, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and zipfile.is_zipfile(destination):
        with zipfile.ZipFile(destination) as z:
            if z.testzip() is None:
                return
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60) as r:
        total = int(r.headers['Content-Length'])
    chunk = 4*1024*1024
    parts = destination.parent/(destination.name+'.parts')
    parts.mkdir(exist_ok=True)

    def fetch(i):
        a, b = i*chunk, min(total, (i+1)*chunk)-1
        path = parts/f'{i:04d}'
        if path.exists() and path.stat().st_size == b-a+1:
            return path
        for attempt in range(4):
            try:
                req = urllib.request.Request(url+f'?gesture_chunk={i}', headers={'Range':f'bytes={a}-{b}'})
                with urllib.request.urlopen(req, timeout=90) as r:
                    if r.status != 206 or r.headers.get('Content-Range') != f'bytes {a}-{b}/{total}':
                        raise RuntimeError('Server did not honor requested byte range')
                    data = r.read(b-a+2)
                if len(data) != b-a+1:
                    raise RuntimeError('Incomplete HTTP range')
                path.write_bytes(data)
                print(f'{destination.name}: chunk {i+1}/{(total+chunk-1)//chunk}', flush=True)
                return path
            except Exception:
                if attempt == 3:
                    raise
                time.sleep(1+attempt)
    with ThreadPoolExecutor(max_workers=6) as pool:
        paths = list(pool.map(fetch, range((total+chunk-1)//chunk)))
    candidate = destination.with_suffix('.complete')
    with candidate.open('wb') as out:
        for path in paths:
            out.write(path.read_bytes())
    with zipfile.ZipFile(candidate) as z:
        if z.testzip() is not None:
            raise RuntimeError('ZIP CRC check failed')
    candidate.replace(destination)


if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser();p.add_argument('url');p.add_argument('destination')
    a = p.parse_args();download(a.url, a.destination)
