#!/usr/bin/env python3
"""make-library.py — 扫描 music/ 目录，重建 iPod 曲库 JSON

用法:
    python3 make-library.py            # 重建 includes/ipod/data/us/en-US.json
    python3 make-library.py /path/to/dir  # 也可以扫其他目录

规则:
    - 支持 mp3 / flac / m4a / wav / ogg / opus / aiff
    - 歌名/歌手/专辑优先读文件标签(需 ffprobe)，缺失时用文件名/文件夹名
    - 每张专辑(按 albumName)自动生成一个播放列表
    - 原版 Apple 曲库备份在 en-US.json.orig（首次运行时生成）
"""
import json
import os
import subprocess
import sys
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, 'includes/ipod/data/us/en-US.json')
AUDIO_EXT = ('.mp3', '.flac', '.m4a', '.wav', '.ogg', '.opus', '.aiff', '.aif')


def probe(path):
    r = subprocess.run(
        ['ffprobe', '-v', 'quiet', '-show_entries',
         'format=duration:format_tags=title,artist,album,album_artist',
         '-of', 'json', path],
        capture_output=True, text=True)
    try:
        meta = json.loads(r.stdout or '{}')
    except json.JSONDecodeError:
        meta = {}
    fmt = meta.get('format', {})
    tags = fmt.get('tags', {})
    return tags, float(fmt.get('duration', 0) or 0)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'music')
    files = []
    for root, dirs, fs in os.walk(src):
        dirs.sort()
        for f in sorted(fs):
            if f.lower().endswith(AUDIO_EXT):
                files.append(os.path.relpath(os.path.join(root, f), HERE))
    if not files:
        sys.exit(f'在 {src} 没找到音频文件')

    songs, by_artist = [], {}
    for i, path in enumerate(files, 1):
        tags, dur = probe(path)
        name = tags.get('title') or os.path.splitext(os.path.basename(path))[0]
        artist = tags.get('artist') or tags.get('album_artist') or '未知艺术家'
        album = tags.get('album') or os.path.basename(os.path.dirname(path))
        sid = f'local-{i:04d}'
        songs.append({
            'id': sid,
            'name': name,
            'artistName': artist,
            'artistIds': [f'local-artist-{artist}'],
            'previewUrl': quote(path),
            'albumName': album,
            'durationInMillis': int(round(dur * 1000)),
            'playParams': {'id': sid, 'kind': 'song'},
            'url': '/',
        })
        by_artist.setdefault(artist, []).append(sid)
        print(f'  {sid}  {artist} - {name}  [{album}]  {dur:.0f}s')

    artists = [{'id': f'local-artist-{a}', 'name': a, 'songIds': ids}
               for a, ids in by_artist.items()]
    albums = {}
    for s in songs:
        albums.setdefault(s['albumName'], []).append(s['id'])
    playlists = [{
        'id': f'local-pl-{j:03d}', 'name': alb, 'url': '/',
        'songIds': ids, 'trackCount': len(ids), 'curatorName': '我',
    } for j, (alb, ids) in enumerate(albums.items(), 1)]

    out = {'schemaVersion': 3, 'storefront': 'us', 'language': 'en-US',
           'songs': songs, 'artists': artists, 'playlists': playlists}

    if not os.path.exists(TARGET + '.orig'):
        os.replace(TARGET, TARGET + '.orig')
        print('\n原版 Apple 曲库已备份为 en-US.json.orig')
    with open(TARGET, 'w') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f'完成: {len(songs)} 首 / {len(artists)} 位艺术家 / {len(playlists)} 个播放列表')
    print('刷新 iPod 页面即可看到新曲库')


if __name__ == '__main__':
    main()
