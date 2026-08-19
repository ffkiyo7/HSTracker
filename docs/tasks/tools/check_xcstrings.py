#!/usr/bin/env python3
"""String Catalog 校验器（Phase 3 用）。

用法：
    python3 docs/tasks/tools/check_xcstrings.py            # 对比 HEAD 校验全部 .xcstrings
    python3 docs/tasks/tools/check_xcstrings.py --baseline <git-ref>
    python3 docs/tasks/tools/check_xcstrings.py --coverage-only

校验项（任一失败 → 退出码 1）：
  E1  文件不是合法 JSON
  E2  文件格式偏离 Xcode 的规范写法（见 canonical() —— 保证 diff 只有真实改动）
  E3  相对 baseline 增加或删除了 key
  E4  相对 baseline 改动了 zh-Hans 以外的任何语言
  E5  相对 baseline 改动或删除了已存在的 zh-Hans 译文（只允许**补空缺**；
      需要修改既有译文的任务用 --allow-zh-edit 放行）
  E6  zh-Hans 与英文原文的格式化占位符（%@ / %d / %1$@ …）不一致
  E7  zh-Hans 的 state 不是 "translated"
  E8  zh-Hans 值为空白

警告（不影响退出码）：
  W1  zh-Hans 与 en 完全相同（品牌名如 HSTracker / HSReplay 属正常）
"""
import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys

# 严格匹配真正的格式化说明符：标志位里**不含空格**，否则 "90% CI" 会被误判成 "% C"。
SPEC = re.compile(r'%(?:(\d+)\$)?[-+0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfFeEgGcCsSpaA%])')


def canonical(data):
    """Xcode 写 .xcstrings 的格式：2 空格缩进、" : " 分隔、不转义非 ASCII、无尾换行。"""
    return json.dumps(data, indent=2, ensure_ascii=False, separators=(',', ' : '))


def load(path):
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    return text, json.loads(text, object_pairs_hook=collections.OrderedDict)


def load_baseline(ref, path):
    try:
        blob = subprocess.run(['git', 'show', f'{ref}:{path}'], capture_output=True, check=True).stdout
    except subprocess.CalledProcessError:
        return None
    return json.loads(blob.decode('utf-8'), object_pairs_hook=collections.OrderedDict)


def unit(entry, lang):
    loc = entry.get('localizations', {}).get(lang)
    if not loc:
        return None
    return loc.get('stringUnit')


def value(entry, lang):
    u = unit(entry, lang)
    if not u:
        return None
    v = u.get('value', '')
    return v if v.strip() else None


def specs(text):
    return sorted(m.group(2) for m in SPEC.finditer(text) if m.group(2) != '%')


def translatable(entry):
    return entry.get('shouldTranslate') is not False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--baseline', default='HEAD')
    ap.add_argument('--coverage-only', action='store_true')
    ap.add_argument('--allow-zh-edit', action='store_true',
                    help='允许修改已存在的 zh-Hans 译文（仅采纳 gaenyong 差异译法的任务需要）')
    ap.add_argument('--allow-new-key', action='append', default=[], metavar='KEY',
                    help='允许新增的 key，可重复。只给 T3 补的 Archive / Unarchive 用')
    args = ap.parse_args()

    errors, warnings, rows = [], [], []
    paths = sorted(p for p in glob.glob('**/*.xcstrings', recursive=True)
                   if not p.startswith('.refs'))
    if not paths:
        print('找不到任何 .xcstrings —— 请在仓库根目录运行', file=sys.stderr)
        return 2

    for path in paths:
        try:
            text, data = load(path)
        except json.JSONDecodeError as exc:
            errors.append(f'E1 {path}: JSON 解析失败 —— {exc}')
            continue

        if canonical(data) != text and os.path.basename(path) != 'Localizable.xcstrings':
            errors.append(f'E2 {path}: 格式偏离规范写法。'
                          f'用 canonical() 的参数重新序列化，不要改缩进/分隔符/尾换行')

        strings = data.get('strings', {})
        base = None if args.coverage_only else load_baseline(args.baseline, path)

        total = missing = 0
        for key, entry in strings.items():
            if not translatable(entry):
                continue
            total += 1
            en, zh = value(entry, 'en'), value(entry, 'zh-Hans')
            if zh is None:
                missing += 1
            else:
                u = unit(entry, 'zh-Hans')
                if u.get('state') != 'translated':
                    errors.append(f'E7 {path} [{key}]: zh-Hans state={u.get("state")!r}，应为 "translated"')
                if en and specs(en) != specs(zh):
                    errors.append(f'E6 {path} [{key}]: 占位符不一致 en={specs(en)} zh={specs(zh)}\n'
                                  f'      en={en!r}\n      zh={zh!r}')
                if en and en == zh:
                    warnings.append(f'W1 {path} [{key}]: zh-Hans 与 en 相同 —— {en!r}')
            loc = entry.get('localizations', {}).get('zh-Hans')
            if loc and not value(entry, 'zh-Hans') and 'stringUnit' in loc:
                errors.append(f'E8 {path} [{key}]: zh-Hans 值为空白')

        rows.append((missing, total, path))

        if base is None:
            continue
        old = base.get('strings', {})
        added, removed = set(strings) - set(old), set(old) - set(strings)
        for key in sorted(added - set(args.allow_new_key)):
            errors.append(f'E3 {path} [{key}]: 新增了 baseline 里没有的 key')
        for key in sorted(removed):
            errors.append(f'E3 {path} [{key}]: 删除了 baseline 里存在的 key')
        for key in sorted(set(strings) & set(old)):
            new_locs = strings[key].get('localizations', {})
            old_locs = old[key].get('localizations', {})
            for lang in sorted(set(new_locs) | set(old_locs)):
                if lang == 'zh-Hans':
                    continue
                if new_locs.get(lang) != old_locs.get(lang):
                    errors.append(f'E4 {path} [{key}]: 改动了 {lang} 的译文（本阶段只许动 zh-Hans）')
            was = value(old[key], 'zh-Hans')
            now = value(strings[key], 'zh-Hans')
            if was is not None and was != now and not args.allow_zh_edit:
                errors.append(f'E5 {path} [{key}]: 改动了已存在的 zh-Hans\n'
                              f'      before={was!r}\n      after ={now!r}')

    total_missing = sum(r[0] for r in rows)
    total_keys = sum(r[1] for r in rows)
    print('zh-Hans 覆盖率（缺失 / 总数）')
    for missing, total, path in sorted(rows, reverse=True):
        flag = '  ' if missing else '✓ '
        print(f'  {flag}{missing:4d} / {total:4d}  {path}')
    done = total_keys - total_missing
    pct = 100.0 * done / total_keys if total_keys else 100.0
    print(f'\n合计：{done} / {total_keys} 已翻译（{pct:.1f}%），仍缺 {total_missing}')

    for w in warnings:
        print(f'\n[warn] {w}')
    for e in errors:
        print(f'\n[FAIL] {e}')

    if errors:
        print(f'\n✗ {len(errors)} 项校验失败')
        return 1
    print('\n✓ 校验通过')
    return 0


if __name__ == '__main__':
    sys.exit(main())
