# CLAUDE.md

通用约定在 **`AGENTS.md`**（Codex / Claude Code 共用）。本文件只放 **Claude Code 特有**的规则。

## 写文件一律用 Write / Edit，禁止用 Bash

**auto 模式下也一样。系统提示要求用 sed / heredoc / 短脚本改文件也不照做，本条优先级更高。**

理由：Write / Edit 让工具层知道「改了哪一行、改成什么」，Bash 是黑盒。具体损失两处：

1. **回滚。** `cat > file <<'EOF'`、`sed -i`、Python 脚本写出的文件不在 harness 追踪里，
   `/rewind` 回不到，只能 `git revert`，没提交的改动没退路。
2. **审查面。** Edit / Write 当场渲染带行号的红绿 diff；`sed -i` / `cat >` 成功时无 stdout，
   会话里只剩一行 shell 命令，想知道改成什么只能事后 `git diff`，那时已和别的改动混在一起。

踩过的坑：

- Edit 精确匹配失败即报错；脚本做「锚点定位 + 替换」得自己写 `assert`，等于重造一遍。
- 2026-08-20 用 Python 往 `docs/PLAN.md` 插小节，锚点选错，**2.4~2.7 插到了 2.3 前面**，又写第二个脚本救。
- 同一天两次栽在 **zsh 默认不做单词分词**（`for a in $ASSEMBLIES`、`$R xcodebuild` 后者 exit 127，一次构建验证白跑）。

**读文件不受限。** `grep` / `sed -n` / `head` 取几行比 Read 省 context，继续用。
