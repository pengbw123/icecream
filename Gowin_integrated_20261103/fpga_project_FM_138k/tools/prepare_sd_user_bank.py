"""Create the preallocated instrument bank in a mounted FAT32 card root.

Does not format cards or access raw drives. Existing files are never overwritten.
"""
import argparse
from pathlib import Path
import struct
import zlib


def bank_image():
    data = bytearray(17 * 512)
    struct.pack_into('<8sIII', data, 0, b'FMUSER1\0', 1, 8, 260)
    struct.pack_into('<I', data, 508, zlib.crc32(data[:508]))
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='Mounted FAT32 card root, for example E:/')
    args = parser.parse_args()
    target = args.directory / 'FMUSER.BIN'
    with target.open('xb') as stream:
        stream.write(bank_image())
        stream.flush()
    print('Created {} (8704 bytes, 8 empty slots).'.format(target))


if __name__ == '__main__':
    main()
