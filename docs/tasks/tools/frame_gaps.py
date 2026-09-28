#!/usr/bin/env python3
"""把录屏切成「相邻新画面的间隔」分布，用来判断掉帧。

用法：

    ffmpeg -v error -i rec.mp4 \
      -vf "crop=1100:300:410:450,tblend=all_mode=difference,signalstats,metadata=print:file=yavg.txt" \
      -an -f null -
    python3 docs/tasks/tools/frame_gaps.py yavg.txt [--busy] [--fps 120]

`crop` 取游戏区的一条带，避开左右两侧的 overlay 面板；单行像素扫描不可用，
炉石的背景噪声太大，必须取带求区域均值。`tblend=difference` 之后每帧的
`YAVG` 就是它与前一帧的平均绝对差，超过阈值即视为「一张新画面」。

**`--busy` 基本上是必须加的。** 不加就是整段统计，而两段录像的内容和空闲时长各不相同，
「没有新画面」和「掉帧」在指标上无法区分 —— 2026-08-21 那次对照里，整段统计让 Release
看起来比 Debug 差一倍（≥4 帧 3.9% vs 2.0%），按活跃时段归一化之后两者其实一致。

阈值敏感，所以默认一次跑三个值；跨录像对比必须用同一个阈值。
"""
import argparse
from pathlib import Path

WINDOW_SECONDS = 1.0
BUSY_RATIO = 0.60     # 滑窗内新画面占比达到这个值，才算「动画确实在进行」
MAX_GAP_FRAMES = 24   # 超过这个间隔算空闲，不是掉帧


def read_yavg(path):
    vals = []
    with open(path) as fh:
        for line in fh:
            if line.startswith('lavfi.signalstats.YAVG='):
                vals.append(float(line.split('=', 1)[1]))
    return vals


def busy_mask(is_new, window, ratio):
    n = len(is_new)
    prefix = [0] * (n + 1)
    for i, v in enumerate(is_new):
        prefix[i + 1] = prefix[i] + (1 if v else 0)
    mask = [False] * n
    need = window * ratio
    for start in range(0, n - window + 1):
        if prefix[start + window] - prefix[start] >= need:
            for i in range(start, start + window):
                mask[i] = True
    return mask


def analyze(vals, threshold, fps, busy_only):
    is_new = [v > threshold for v in vals]
    if busy_only:
        mask = busy_mask(is_new, int(fps * WINDOW_SECONDS), BUSY_RATIO)
    else:
        mask = [True] * len(vals)
    counted = sum(mask)
    if not counted:
        print(f'  threshold {threshold}: 没有活跃时段')
        return

    new_idx = [i for i, v in enumerate(is_new) if v and mask[i]]
    gaps = []
    for a, b in zip(new_idx, new_idx[1:]):
        gap = b - a
        if gap <= MAX_GAP_FRAMES and all(mask[a:b + 1]):
            gaps.append(gap)
    if not gaps:
        print(f'  threshold {threshold}: 活跃时段里没有间隔样本')
        return

    buckets = {1: 0, 2: 0, 3: 0, 4: 0}
    for gap in gaps:
        buckets[gap if gap < 4 else 4] += 1
    total = len(gaps)
    over33 = sum(1 for gap in gaps if gap > fps * 0.033)

    scope = f'活跃 {counted/fps:.1f}s / 全长 {len(vals)/fps:.1f}s' if busy_only \
        else f'全长 {len(vals)/fps:.1f}s'
    print(f'  threshold {threshold}: {scope}，间隔样本 {total}')
    print(f'    1 帧 {100*buckets[1]/total:5.1f}%   2 帧 {100*buckets[2]/total:5.1f}%   '
          f'3 帧 {100*buckets[3]/total:5.1f}%   >=4 帧 {100*buckets[4]/total:5.1f}%')
    print(f'    >33ms 空档 {over33} 次（{over33/(counted/fps)*40:.0f} 次/40s），'
          f'最长 {max(gaps)/fps*1000:.0f}ms')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('yavg_file', type=Path, help='metadata=print 产出的文件')
    parser.add_argument('--busy', action='store_true',
                        help='只统计动画进行中的时段（跨录像对比时必须加）')
    parser.add_argument('--fps', type=float, default=120.0)
    parser.add_argument('--threshold', type=float, action='append',
                        help='可重复；默认跑 0.05 / 0.10 / 0.20 三个')
    args = parser.parse_args()

    vals = read_yavg(args.yavg_file)
    print(f'{args.yavg_file.name}: {len(vals)} 帧 / {len(vals)/args.fps:.1f}s'
          f'{"（只统计活跃时段）" if args.busy else "（整段，注意内容差异会造成假象）"}')
    for threshold in args.threshold or (0.05, 0.10, 0.20):
        analyze(vals, threshold, args.fps, args.busy)


if __name__ == '__main__':
    main()
