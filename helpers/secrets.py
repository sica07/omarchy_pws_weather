#!/usr/bin/env python3
"""Private credential storage. Requests/replies travel only over pipes, never argv."""
import fcntl
import json
import os
from pathlib import Path
import stat
import sys

KEYS = ('apiKey', 'meteoblueApiKey')
LIMIT = 16384


def credentials(value):
    if not isinstance(value, dict):
        raise ValueError('Invalid credentials')
    result = {}
    for key in KEYS:
        if key in value:
            item = value[key]
            if not isinstance(item, str) or len(item) > 4096 or any(ord(c) < 32 for c in item):
                raise ValueError('Invalid credential')
            result[key] = item.strip()
    return result


def private_file(directory, name, flags):
    fd = os.open(name, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError('Unsafe file')
        os.fchmod(fd, 0o600)
        return fd
    except Exception:
        os.close(fd)
        raise


def read(directory):
    try:
        fd = private_file(directory, 'secrets.json', os.O_RDONLY)
    except FileNotFoundError:
        return {}
    with os.fdopen(fd) as stream:
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError('Oversized file')
    return credentials(json.loads(data))


def save(directory, value):
    name = '.secrets-' + os.urandom(12).hex()
    try:
        fd = private_file(directory, name, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, 'secrets.json', src_dir_fd=directory, dst_dir_fd=directory)
        os.fsync(directory)
        if read(directory) != value:
            raise ValueError('Verification failed')
    finally:
        try:
            os.unlink(name, dir_fd=directory)
        except FileNotFoundError:
            pass


def handle(request):
    os.umask(0o077)
    folder = Path.home() / '.local/share/omarchy_pws_weather'
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        if os.fstat(directory).st_uid != os.getuid():
            raise ValueError('Unsafe directory')
        os.fchmod(directory, 0o700)
        lock = private_file(directory, '.lock', os.O_RDWR | os.O_CREAT)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            existing = read(directory)  # Refuse corrupt or unsafe stores, even on save.
            action = request.get('action')
            if action == 'load':
                legacy = credentials(request.get('legacy', {}))
                # An existing value (including an intentionally empty key) wins.
                value = {key: existing.get(key, legacy.get(key, '')) for key in KEYS}
            elif action == 'save':
                incoming = credentials(request.get('secrets'))
                if set(incoming) != set(KEYS):
                    raise ValueError('Incomplete save')
                value = incoming
            else:
                raise ValueError('Unknown action')
            if existing != value:
                save(directory, value)
            return {'ok': True, 'secrets': value}
        finally:
            os.close(lock)
    finally:
        os.close(directory)


def main():
    try:
        raw = sys.stdin.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise ValueError('Oversized request')
        result = handle(json.loads(raw))
    except Exception:
        # Never print paths, request data, keys or exception messages.
        print(json.dumps({'ok': False}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
