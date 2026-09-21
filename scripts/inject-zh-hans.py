#!/usr/bin/env python3
"""把我们的 zh-Hans 译文注入上游版 String Catalog。

重建 fork 时用：上游版 `.xcstrings` 当底，我们的同名 catalog 只贡献 zh-Hans。
输出与上游版的差异只有 zh-Hans：不增删 key、不动其他语言、不改格式。

用法：
    # 批量干跑：上游全部 catalog × 我们的 HEAD，输出到目录（保持仓库内相对路径）
    python3 scripts/inject-zh-hans.py --out-dir /tmp/merged

    # 指定两侧来源（git ref 或工作区路径都行）
    python3 scripts/inject-zh-hans.py --upstream-ref upstream/master --ours-ref HEAD \\
        --out-dir /tmp/merged --report /tmp/merged/report.json

    # 单文件：--upstream / --ours 可写 "<git-ref>:<path>" 或文件路径
    python3 scripts/inject-zh-hans.py --upstream upstream/master:A.xcstrings \\
        --ours HEAD:A.xcstrings --out /tmp/A.xcstrings

    # 幂等验证：把上一次的输出当上游再跑一次，两次结果应逐字节相同
    python3 scripts/inject-zh-hans.py --upstream /tmp/merged/A.xcstrings \\
        --ours HEAD:A.xcstrings --out /tmp/A2.xcstrings

约定：
  * 上游已有 zh-Hans 且与我们不同 → 默认取我们的（`--on-conflict upstream` 可反转），计入报告。
  * 上游没有的 key / 整个 catalog → 不注入，计入报告。
  * `shouldTranslate: false` 的条目跳过。
  * 写出前强制两道自检：上游原文必须能「解析 → 原样写回」逐字节还原；
    输出与上游的结构差异必须只在 zh-Hans。任一不过就报错退出，不落盘。
只依赖 Python 3 标准库。
"""
import argparse
import collections
import json
import os
import subprocess
import sys

OrderedDict = collections.OrderedDict
LANG = 'zh-Hans'


class FormatError(Exception):
    pass


# ---------------------------------------------------------------- 序列化


class Style(collections.namedtuple('Style', 'sep blank_empty trailing_newline')):
    """一个 catalog 的排版风格。

    sep             key 与 value 的分隔符：Xcode 写 `" : "`，别的工具写 `": "`。
    blank_empty     空容器写成 `{\\n\\n<缩进>}`（Xcode）还是 `{}`。
    trailing_newline 末尾有没有换行。
    """

    CANDIDATES = [(sep, blank, nl)
                  for sep in (' : ', ': ')
                  for blank in (True, False)
                  for nl in (False, True)]

    @classmethod
    def detect(cls, text, data):
        """挑出能把 data 原样写回成 text 的风格；挑不出就是格式没吃透，直接报错。"""
        for combo in cls.CANDIDATES:
            style = cls(*combo)
            if dumps(data, style) == text:
                return style
        raise FormatError('无法复现原文件的排版（解析 → 写回不是逐字节一致）')


def _dump(value, indent, style, out):
    pad = ' ' * indent
    if isinstance(value, dict):
        if not value:
            out.append('{\n\n' + pad + '}' if style.blank_empty else '{}')
            return
        out.append('{\n')
        items = list(value.items())
        for i, (key, val) in enumerate(items):
            out.append(' ' * (indent + 2))
            out.append(json.dumps(key, ensure_ascii=False))
            out.append(style.sep)
            _dump(val, indent + 2, style, out)
            out.append(',\n' if i < len(items) - 1 else '\n')
        out.append(pad + '}')
    elif isinstance(value, list):
        if not value:
            out.append('[\n\n' + pad + ']' if style.blank_empty else '[]')
            return
        out.append('[\n')
        for i, val in enumerate(value):
            out.append(' ' * (indent + 2))
            _dump(val, indent + 2, style, out)
            out.append(',\n' if i < len(value) - 1 else '\n')
        out.append(pad + ']')
    else:
        out.append(json.dumps(value, ensure_ascii=False))


def dumps(data, style):
    out = []
    _dump(data, 0, style, out)
    if style.trailing_newline:
        out.append('\n')
    return ''.join(out)


# ---------------------------------------------------------------- 读取


def read_source(spec):
    """spec 是工作区路径，或 `<git-ref>:<repo 内路径>`。返回文本。"""
    if os.path.exists(spec):
        with open(spec, encoding='utf-8') as fh:
            return fh.read()
    if ':' not in spec:
        raise FormatError(f'找不到 {spec}')
    return git(['show', spec])


def git(args):
    proc = subprocess.run(['git'] + args, capture_output=True)
    if proc.returncode != 0:
        raise FormatError(f'git {" ".join(args)} 失败：{proc.stderr.decode("utf-8", "replace").strip()}')
    return proc.stdout.decode('utf-8')


def catalogs(ref):
    names = git(['ls-tree', '-r', '--name-only', ref]).split('\n')
    return sorted(n for n in names if n.endswith('.xcstrings'))


def parse(text):
    return json.loads(text, object_pairs_hook=OrderedDict)


def zh_unit(entry):
    """返回该条目可用的 zh-Hans localization 对象（值非空白才算），否则 None。"""
    loc = entry.get('localizations', {}).get(LANG)
    if not isinstance(loc, dict):
        return None
    unit = loc.get('stringUnit')
    if not isinstance(unit, dict) or not str(unit.get('value', '')).strip():
        return None
    return loc


def put_sorted(mapping, key, value):
    """插入后保持键序；原来就没排序的话追加到末尾（不打乱既有顺序）。"""
    keys = list(mapping)
    if key in mapping:
        mapping[key] = value
        return
    if keys != sorted(keys):
        mapping[key] = value
        return
    rebuilt = OrderedDict()
    placed = False
    for existing in keys:
        if not placed and key < existing:
            rebuilt[key] = value
            placed = True
        rebuilt[existing] = mapping[existing]
    if not placed:
        rebuilt[key] = value
    mapping.clear()
    mapping.update(rebuilt)


# ---------------------------------------------------------------- 注入


def inject(upstream, ours, on_conflict='ours'):
    """返回 (合并后的数据, 统计)。upstream / ours 都是已解析的 OrderedDict。"""
    merged = json.loads(json.dumps(upstream, ensure_ascii=False), object_pairs_hook=OrderedDict)
    up_strings = merged.get('strings', OrderedDict())
    our_strings = ours.get('strings', OrderedDict())

    stats = {
        'injected': 0,      # 上游没有 zh-Hans，补上
        'already_same': 0,  # 两边 zh-Hans 相同
        'overridden': 0,    # 两边不同，按 on_conflict 取我们的
        'kept_upstream': 0, # 两边不同，保留上游的
        'skipped_no_zh': 0, # 我们也没有译文
        'skipped_untranslatable': 0,
        'dropped_keys': [],      # 我们有、上游已无的 key
        'dropped_keys_with_zh': [],
        'conflicts': [],         # (key, 上游译文, 我们的译文)
    }

    for key, our_entry in our_strings.items():
        if key not in up_strings:
            stats['dropped_keys'].append(key)
            if zh_unit(our_entry) is not None:
                stats['dropped_keys_with_zh'].append(key)

    for key, entry in up_strings.items():
        if entry.get('shouldTranslate') is False:
            stats['skipped_untranslatable'] += 1
            continue
        our_entry = our_strings.get(key)
        our_loc = zh_unit(our_entry) if our_entry is not None else None
        if our_loc is None:
            stats['skipped_no_zh'] += 1
            continue
        up_loc = entry.get('localizations', {}).get(LANG)
        if up_loc is None:
            stats['injected'] += 1
        elif up_loc == our_loc:
            stats['already_same'] += 1
            continue
        else:
            stats['conflicts'].append((key,
                                       up_loc.get('stringUnit', {}).get('value'),
                                       our_loc.get('stringUnit', {}).get('value')))
            if on_conflict == 'upstream':
                stats['kept_upstream'] += 1
                continue
            stats['overridden'] += 1
        if 'localizations' not in entry:
            put_sorted(entry, 'localizations', OrderedDict())
        put_sorted(entry['localizations'], LANG,
                   json.loads(json.dumps(our_loc, ensure_ascii=False), object_pairs_hook=OrderedDict))
    return merged, stats


def verify(upstream, merged):
    """输出相对上游的差异必须只在 zh-Hans。返回违规说明列表。"""
    bad = []
    if list(upstream) != list(merged):
        bad.append('顶层键集合/顺序变了')
    for top in upstream:
        if top != 'strings' and upstream[top] != merged.get(top):
            bad.append(f'顶层 {top} 变了')
    up_s, mg_s = upstream.get('strings', {}), merged.get('strings', {})
    if list(up_s) != list(mg_s):
        bad.append('strings 的 key 集合或顺序变了')
        return bad
    for key in up_s:
        up_e, mg_e = up_s[key], mg_s[key]
        extra = set(mg_e) - set(up_e)
        if extra - {'localizations'} or set(up_e) - set(mg_e):
            bad.append(f'[{key}] 条目字段变了：{sorted(set(mg_e) ^ set(up_e))}')
            continue
        for field in up_e:
            if field != 'localizations' and up_e[field] != mg_e[field]:
                bad.append(f'[{key}] 字段 {field} 变了')
        up_l, mg_l = up_e.get('localizations', {}), mg_e.get('localizations', {})
        if set(up_l) - set(mg_l) or (set(mg_l) - set(up_l)) - {LANG}:
            bad.append(f'[{key}] 语言集合变了：{sorted(set(mg_l) ^ set(up_l))}')
            continue
        for lang in up_l:
            if lang != LANG and up_l[lang] != mg_l[lang]:
                bad.append(f'[{key}] 改动了 {lang}')
    return bad


def merge_text(up_text, our_text, on_conflict='ours'):
    """返回 (输出文本, 统计)。上游原文必须能原样写回，否则抛 FormatError。"""
    up_data = parse(up_text)
    style = Style.detect(up_text, up_data)
    merged, stats = inject(up_data, parse(our_text), on_conflict)
    bad = verify(up_data, merged)
    if bad:
        raise FormatError('结构自检失败：' + '；'.join(bad[:5]))
    return dumps(merged, style), stats


# ---------------------------------------------------------------- CLI


def run_one(up_spec, our_spec, out_path, on_conflict, quiet):
    up_text = read_source(up_spec)
    our_text = read_source(our_spec)
    text, stats = merge_text(up_text, our_text, on_conflict)
    if out_path:
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, 'w', encoding='utf-8') as fh:
            fh.write(text)
    if not quiet:
        print(f'{out_path or up_spec}: 注入 {stats["injected"]}，'
              f'覆盖 {stats["overridden"]}，保留上游 {stats["kept_upstream"]}，'
              f'相同 {stats["already_same"]}，跳过 {stats["skipped_no_zh"]}，'
              f'字节无变化 {text == up_text}')
    return stats


def main():
    ap = argparse.ArgumentParser(description='把我们的 zh-Hans 注入上游版 .xcstrings')
    ap.add_argument('--upstream', help='单文件模式：上游版 catalog（路径或 <ref>:<path>）')
    ap.add_argument('--ours', help='单文件模式：我们的 catalog（路径或 <ref>:<path>）')
    ap.add_argument('--out', help='单文件模式：输出路径；不给就只跑检查不落盘')
    ap.add_argument('--upstream-ref', default='upstream/master', help='批量模式的上游 git ref')
    ap.add_argument('--ours-ref', default='HEAD', help='批量模式我们这侧的 git ref')
    ap.add_argument('--out-dir', help='批量模式输出目录，按仓库内相对路径落盘')
    ap.add_argument('--on-conflict', choices=('ours', 'upstream'), default='ours',
                    help='两边 zh-Hans 不同时取哪边，默认 ours')
    ap.add_argument('--report', help='把统计写成 JSON')
    ap.add_argument('-q', '--quiet', action='store_true')
    args = ap.parse_args()

    try:
        if args.upstream or args.ours:
            if not (args.upstream and args.ours):
                ap.error('--upstream 和 --ours 要成对给')
            stats = run_one(args.upstream, args.ours, args.out, args.on_conflict, args.quiet)
            report = {'files': {args.upstream: stats}}
        else:
            if not args.out_dir:
                ap.error('批量模式需要 --out-dir')
            up_list, our_list = catalogs(args.upstream_ref), catalogs(args.ours_ref)
            report = {
                'upstream_ref': args.upstream_ref, 'ours_ref': args.ours_ref,
                'on_conflict': args.on_conflict,
                'upstream_only_catalogs': [p for p in up_list if p not in our_list],
                'ours_only_catalogs': [p for p in our_list if p not in up_list],
                'files': {},
            }
            for path in up_list:
                our_spec = f'{args.ours_ref}:{path}' if path in our_list else None
                out_path = os.path.join(args.out_dir, path)
                if our_spec is None:
                    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
                    text = read_source(f'{args.upstream_ref}:{path}')
                    with open(out_path, 'w', encoding='utf-8') as fh:
                        fh.write(text)
                    report['files'][path] = {'no_counterpart': True}
                    if not args.quiet:
                        print(f'{path}: 我们没有这个 catalog，原样拷贝')
                    continue
                report['files'][path] = run_one(f'{args.upstream_ref}:{path}', our_spec,
                                                out_path, args.on_conflict, args.quiet)
    except FormatError as exc:
        print(f'错误：{exc}', file=sys.stderr)
        return 1

    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
