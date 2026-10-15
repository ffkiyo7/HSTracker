#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""红龙贼公式表 · 只算法力的逐 token 推演器（只读 formulas.json，只打印）

2026-09-11 由推演代理写成，用来核对 formulas.json 与 red-dragon-card-model.md 的规则是否一致。
它只模拟法力 / 减费层 / 场面名单 / 阿莱次数，不模拟伤害以外的场面细节。
留在这里是给 T1 做参考：fixture 行 → 初始状态的映射约定（seed_for / run_row）以它为准。

用法：python3 sim.py            # 在本目录运行
"""
import json, os, sys

JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "formulas.json")

PRINTED = {'鱼':4,'狐':2,'刀':4,'暗':5,'牛':4,'晦':3,'龙':9,
           '舞':3,'幻':4,'步':0,'骨':2,'伺':0,'殒':0,'币':0,'帷幕':3}
MINIONS = set('鱼狐刀暗牛晦龙')
SPELLS  = set(['舞','幻','步','骨','伺','殒','币','帷幕'])
COMBO   = set(['刀'])                     # 本表出现的连击牌只有刀油
HEALTH  = {'鱼':3,'狐':2,'刀':3,'暗':4,'牛':4,'晦':3,'龙':8}
SIDEBOARD = ['舞','幻','龙']
PLACEHOLDER = set(['杂','腾格','某随','鱼之外某随'])
BASE_OVERRIDE = [None]   # 殒命暗影：复制品的费用 = 被复制法术的费用


class Inst:
    """手牌里的一张牌。names = 可能的身份集合（通配：暗的复制 / 牛的发现）。"""
    __slots__ = ('names','ench','kind')
    def __init__(self, names, ench=None, kind='concrete'):
        self.names = set(names)
        self.ench = list(ench or [])     # [('set',1),('delta',-2), ...] 按挂载顺序
        self.kind = kind
    def effbase(self, name):
        v = BASE_OVERRIDE[0] if (name == '殒' and BASE_OVERRIDE[0] is not None) else PRINTED[name]
        for k, x in self.ench:
            v = x if k == 'set' else v + x
        return max(0, v)
    def clone(self):
        return Inst(self.names, self.ench, self.kind)


class Sim:
    def __init__(self, crystals, mana, seed_names, refresh_cap=None):
        self.max_mana = crystals              # 水晶上限（晦鳞复原的 clamp）
        self.mana = mana
        self.cap = refresh_cap if refresh_cap is not None else crystals
        self.layers = []                      # [amount, slots, filt]
        self.board = []                       # [(name, is1x1)]
        self.shark = False
        self.hand = [Inst([n]) for n in seed_names]
        self.sideboard = list(SIDEBOARD)
        self.dmg = 0
        self.log = []
        self.notes = []
        self.force_double_first_combo = False

    # ---- 减费 ----
    def matches(self, name, filt):
        if filt == 'any':   return True
        if filt == 'spell': return name in SPELLS
        if filt == 'combo': return name in COMBO
        return False

    def discount(self, name):
        return sum(l[0] for l in self.layers if self.matches(name, l[2]))

    def consume(self, name):
        keep = []
        for l in self.layers:
            if self.matches(name, l[2]):
                l[1] -= 1
            if l[1] > 0:
                keep.append(l)
        self.layers = keep

    def push(self, amount, slots, filt, times=1):
        for _ in range(times):
            self.layers.append([amount, slots, filt])

    # ---- 手牌取牌 ----
    def candidates(self, name):
        """返回 [(inst, effbase)]，按 effbase 去重排序"""
        out = []
        for inst in self.hand:
            if name in inst.names:
                out.append((inst, inst.effbase(name)))
        return out

    def take(self, name, want_cost, disc):
        """挑一张实例：优先使实际花费 == want_cost；否则最便宜的。返回 (effbase, 可能值集合, 是否缺牌)"""
        cands = self.candidates(name)
        missing = False
        if not cands:
            missing = True
            # 手牌里没有这张：按表值反推一个费用，避免误差级联；[缺牌] 单独报告
            v = PRINTED[name] if want_cost is None else want_cost + disc
            inst = Inst([name], [('set', v)]); self.hand.append(inst)
            cands = [(inst, inst.effbase(name))]
        poss = sorted(set(max(0, eb - disc) for _, eb in cands))
        pick = None
        if want_cost is not None:
            for inst, eb in cands:
                if max(0, eb - disc) == want_cost:
                    pick = (inst, eb); break
        if pick is None:
            pick = min(cands, key=lambda t: t[1])
        inst, eb = pick
        # 通配实例被确定身份：从池中扣除
        if inst.kind == 'etc' and name in self.sideboard:
            self.sideboard.remove(name)
        self.hand.remove(inst)
        return eb, poss, missing

    # ---- 场面 ----
    def rm_board(self, name):
        for i, (n, c) in enumerate(self.board):
            if n == name:
                return self.board.pop(i)
        return None

    def refresh(self, n):
        for _ in range(n):
            self.mana = min(self.mana + 2, self.cap)

    # ---- 打一张牌 ----
    def play(self, tok, table_after):
        name = tok['card']
        tgt = tok.get('target')
        disc = self.discount(name) if name not in PLACEHOLDER else \
               sum(l[0] for l in self.layers if l[2] == 'any')

        BASE_OVERRIDE[0] = PRINTED.get(tgt) if name == '殒' else None
        n_trig0 = 2 if self.shark else 1
        if name in PLACEHOLDER:
            # 占位：从表值反推花费
            cost = None if table_after is None else self.mana - table_after
            poss = None
            eb = None if cost is None else cost + disc
            missing = False
            if cost is None: cost = 0
        else:
            want = None
            poss_after = []
            for _, ebc in self.candidates(name):
                c = max(0, ebc - disc); m = self.mana - c
                if name == '晦':
                    for _ in range(n_trig0): m = min(m + 2, self.cap)
                elif name == '币':
                    m += 1
                poss_after.append(m)
            poss_after = sorted(set(poss_after))
            if table_after is not None:
                if name == '晦':
                    for _, ebc in self.candidates(name) or []:
                        c = max(0, ebc - disc); m = self.mana - c
                        for _ in range(n_trig0):
                            m = min(m + 2, self.cap)
                        if m == table_after:
                            want = c; break
                elif name == '币':
                    want = self.mana - table_after + 1
                else:
                    want = self.mana - table_after
            eb, _p, missing = self.take(name, want, disc)
            poss = poss_after or None
            cost = max(0, eb - disc)

        before = self.mana
        self.mana -= cost
        self.consume(name if name not in PLACEHOLDER else '__any__')
        neg = self.mana < 0

        # ---- 效果 ----
        n_trig = 2 if self.shark else 1
        if name == '鱼':
            self.board.append(('鱼', eb == 1)); self.shark = True
        elif name == '狐':
            self.board.append(('狐', eb == 1))
            self.push(2, 1, 'combo', n_trig)
        elif name == '刀':
            self.board.append(('刀', eb == 1))
            t = n_trig
            if self.force_double_first_combo and not self.shark:
                t = 2                      # 复现「表把首刀当成鲨鱼在场」的算法
            self.push(2, 2, 'any', t)
        elif name == '暗':
            self.board.append(('暗', eb == 1))
            allowed = set(n for n, _ in self.board) if not tgt else {tgt}
            for _ in range(n_trig):
                self.hand.append(Inst(allowed, [('set', 1)], 'shadow'))
        elif name == '牛':
            self.board.append(('牛', eb == 1))
            for _ in range(n_trig):
                if self.sideboard:
                    self.hand.append(Inst(set(self.sideboard), [], 'etc'))
                else:
                    self.notes.append('牛发现时边牌池已空')
        elif name == '晦':
            self.board.append(('晦', eb == 1))
            self.refresh(n_trig)
        elif name == '龙':
            self.board.append(('龙', eb == 1))
            self.dmg += 8 * n_trig
        elif name in ('舞',):
            self._bounce_all()
        elif name == '幻':
            for n, c in list(self.board):
                self.hand.append(Inst([n], [('set', 1)], 'copy'))
        elif name == '步':
            self._step(tgt)
        elif name == '骨':
            self._bone(tgt)
        elif name == '伺':
            self.push(2, 1, 'spell')
        elif name == '币':
            self.mana += 1
        elif name == '殒':
            if tgt:
                # 殒已变形成 tgt 这张法术：按 tgt 结算
                if tgt == '舞': self._bounce_all()
                elif tgt == '步': self._step(None)
                elif tgt == '幻':
                    for n, c in list(self.board):
                        self.hand.append(Inst([n], [('set', 1)], 'copy'))
        elif name == '腾格':
            if tgt: self.rm_board(tgt)
            else:
                for pref in ('刀', '狐', '晦', '牛', '暗'):
                    if self.rm_board(pref): break

        exp = self.mana          # 含晦鳞复原 / 币等效果之后
        self.log.append(dict(card=name, target=tgt, before=before, cost=cost,
                             effbase=eb, disc=disc, expected=exp,
                             table=table_after, poss=poss, missing=missing,
                             neg=neg, after=self.mana))
        return exp

    def _bounce_all(self):
        for n, c in self.board:
            self.hand.append(Inst([n], [('set', 1)], 'bounced'))
        self.board = []
        self.shark = False

    def _step(self, tgt):
        if tgt in (None, '鱼之外某随', '某随'):
            cand = [n for n, _ in self.board if n != '鱼'] or [n for n, _ in self.board]
            tgt = cand[-1] if cand else None
        if tgt is None: return
        self.rm_board(tgt)
        if tgt == '鱼': self.shark = False
        self.hand.append(Inst([tgt], [('delta', -2)], 'stepped'))

    def _bone(self, tgt):
        if tgt is None: return
        ent = None
        for n, c in self.board:
            if n == tgt: ent = (n, c); break
        if ent is None:
            self.notes.append('骨刺目标 %s 不在场' % tgt); return
        hp = 1 if ent[1] else HEALTH.get(tgt, 99)
        if hp <= 3:
            self.rm_board(tgt)
            if tgt == '鱼': self.shark = False
            self.push(2, 1, 'any')
        else:
            self.notes.append('骨刺打不死 %s（%d 血），未产生减费层' % (tgt, hp))


def seed_for(row):
    """fixture 行 → 起始手牌：六个核心随从 + 特殊杂牌各两张 + 常见偷费牌各一张。
    法力 = row.cost（费用列），水晶上限 = row.crystals（水晶列）。"""
    s = ['鱼', '狐', '刀', '暗', '牛', '晦']
    sp = row.get('specialJunk')
    if isinstance(sp, str): sp = [sp]
    for x in (sp or []):
        if x in PRINTED: s.append(x); s.append(x)
    for x in ('步', '骨', '伺', '殒', '币', '帷幕'):
        s.append(x)
    return s


def run_row(row, cap_override=None, resync=True, dbl_first_dao=False):
    steps = row.get('steps') or []
    if not steps or all(s is None for s in steps):
        return None
    crystals = row.get('crystals')
    cost = row.get('cost')
    if cost is None:
        return None
    cap = cap_override if cap_override is not None else (crystals if crystals else 99)
    sim = Sim(crystals or 99, cost, seed_for(row), refresh_cap=cap)
    sim.force_double_first_combo = dbl_first_dao
    res = []
    for pi, ph in enumerate(steps):
        if ph is None:
            res.append(None); continue
        pres = []
        for si, tok in enumerate(ph):
            ta = tok.get('manaAfter')
            sim.play(tok, ta)
            e = dict(sim.log[-1]); e['i'] = si; e['phase'] = pi
            pres.append(e)
            if resync and ta is not None:
                sim.mana = ta          # 对齐表值，避免误差级联
        res.append(pres)
    return sim, res


def score(row, **kw):
    r = run_row(row, **kw)
    if r is None: return None
    sim, res = r
    tot = ok = 0; bad = []
    for ph in res:
        if ph is None: continue
        for e in ph:
            if e['table'] is None: continue
            tot += 1
            if e['expected'] == e['table']: ok += 1
            else: bad.append(e)
    return sim, res, tot, ok, bad


def main():
    doc = json.load(open(JSON, encoding='utf-8'))
    rows = doc['rows']
    TOT = OK = AMB = UNK = 0
    allbad = []
    capnotes = []
    for row in rows:
        s = score(row)
        if s is None: continue
        sim, res, tot, ok, bad = s
        # 若不一致，试试更高的水晶上限
        best = None
        if bad and row.get('crystals'):
            for c in range(row['crystals'], row['crystals'] + 4):
                s2 = score(row, cap_override=c)
                if s2 and not s2[4]:
                    best = c; break
            if best is None:
                for c in range(row['crystals'], row['crystals'] + 4):
                    s2 = score(row, cap_override=c)
                    if s2 and len(s2[4]) < len(bad):
                        best = c; sim, res, tot, ok, bad = s2; break
            else:
                s2 = score(row, cap_override=best)
                sim, res, tot, ok, bad = s2
                capnotes.append((row['id'], row['crystals'], best))
        TOT += tot; OK += ok
        for ph in res or []:
            if ph is None: continue
            for e in ph:
                if e['table'] is None: UNK += 1
                elif e['expected'] == e['table'] and e['poss'] and len(e['poss']) > 1:
                    AMB += 1
        for e in bad: allbad.append((row['id'], e))
        if row.get('damage') is not None and sim.dmg != row['damage']:
            allbad.append((row['id'], dict(card='DMG', target=None, table=row['damage'],
                                           expected=sim.dmg, poss=None, i='-', phase=-1,
                                           missing=False, neg=False, disc=None,
                                           effbase=None, cost=None, before=None)))
    print('== token 级一致率：%d/%d = %.1f%%（%d 个 token 表里没数字，未计入；%d 个费用有多解）'
          % (OK, TOT, 100.0*OK/TOT, UNK, AMB))
    print('\n== 需要「本回合水晶上限 > 水晶列」才自洽的行：')
    for rid, c, need in capnotes:
        print('   %-14s 水晶列=%d  需要上限=%d (+%d)' % (rid, c, need, need - c))
    print('\n== 剩余不一致 %d 条：' % len(allbad))
    for rid, e in allbad:
        print('  %-14s 阶段%s #%-2s %-6s 表=%-4s 推=%-4s 可能值=%s%s%s'
              % (rid, e['phase']+1, e['i'],
                 e['card'] + ('-'+e['target'] if e['target'] else ''),
                 e['table'], e['expected'], e['poss'],
                 ' [手里没这张]' if e['missing'] else '', ' [负费]' if e['neg'] else ''))


if __name__ == '__main__':
    main()
