#!/usr/bin/env python3
"""Turns the rewritten branches from fix_cross_file_branch_sites.py into valid C++.

THE PROBLEM

    fc3_recomp.66.cpp:24625:24: error: expected ';' after goto statement

fix_cross_file_branch_sites.py rewrites `goto loc_83494048;` into `goto fc3_label_83494048(ctx, base);`, which is not
C++: `goto` takes a label, not a call. The intent was "jump into that block and do not come back", which for a shared
epilogue is exactly "call it, then return" — the epilogue ends by returning to the guest's caller.

THE FIX

    if (!ctx.cr0.eq) goto fc3_label_83494048(ctx, base);
    =>
    if (!ctx.cr0.eq) { fc3_label_83494048(ctx, base); return; }

The `return` is required and is what makes this exact rather than an approximation: the block is the callee's epilogue
(pop the frame, restore f30/f31, __restgprlr, return to the guest's caller), so control must not return to the
instruction after the branch in the branching function. A block whose body does NOT end the function (a shared loop
body, say) would need the return left out; that is decided per label by inspecting the wrapper's last statement, and
reported.

An unconditional `goto` (no `if`) becomes `{ f(...); return; }`.

Idempotent: a site already rewritten does not match.

    python3 tools/fix_cross_file_branch_calls.py
    python3 tools/fix_cross_file_branch_calls.py --check
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'app', 'generated')

# `if (<cond>) goto fc3_label_XXXXXXXX(ctx, base);` possibly wrapped in braces already.
COND_RE = re.compile(r'if\s*\((?P<cond>[^{}\n]*?)\)\s*goto\s+fc3_label_(?P<h>[0-9A-Fa-f]+)\(ctx, base\)\s*;')
# A bare `goto fc3_label_XXXXXXXX(ctx, base);` at statement level.
BARE_RE = re.compile(r'^([ \t]*)goto\s+fc3_label_(?P<h>[0-9A-Fa-f]+)\(ctx, base\)\s*;[ \t]*$', re.M)
WRAPPER_DEF = re.compile(r'void\s+fc3_label_(?P<h>[0-9A-Fa-f]+)\s*\(PPCContext& __restrict ctx, uint8_t\* base\)\s*\{')


def wrapper_returns_after(tree, label):
    """True when the wrapper's body ends by returning or jumping away (so the caller must not fall through)."""
    for name in sorted(os.listdir(tree)):
        if not (name.startswith('fc3_recomp.') and name.endswith('.cpp')):
            continue
        path = os.path.join(tree, name)
        with open(path, encoding='utf-8', errors='replace') as fh:
            lines = fh.readlines()
        for i, line in enumerate(lines):
            m = WRAPPER_DEF.match(line)
            if not m or m.group('h').upper() != label.upper():
                continue
            body = []
            for j in range(i + 1, len(lines)):
                if lines[j].rstrip() == '}':
                    break
                s = lines[j].strip()
                if s and not s.startswith('//'):
                    body.append(s)
            if not body:
                return True
            last = body[-1]
            return bool(re.search(r'\b(return|goto)\b', last))
    return True  # conservative: assume the caller must return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gen', action='append', default=[])
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    trees = args.gen or [os.path.join(GEN, n) for n in sorted(os.listdir(GEN))
                         if os.path.isdir(os.path.join(GEN, n))]

    total = 0
    for tree in trees:
        files = [os.path.join(tree, n) for n in sorted(os.listdir(tree))
                 if n.startswith('fc3_recomp.') and n.endswith('.cpp')]
        returns = {}
        for f in files:
            with open(f, encoding='utf-8') as fh:
                text = fh.read()

            def sub_cond(m):
                h = m.group('h').upper()
                if h not in returns:
                    returns[h] = wrapper_returns_after(tree, h)
                tail = '; return; }' if returns[h] else '; }'
                return f'if ({m.group("cond")}) {{ fc3_label_{h}(ctx, base){tail}'

            new, n_cond = COND_RE.subn(sub_cond, text)

            def sub_bare(m):
                h = m.group('h').upper()
                if h not in returns:
                    returns[h] = wrapper_returns_after(tree, h)
                tail = '; return; }' if returns[h] else '; }'
                return f'{m.group(1)}{{ fc3_label_{h}(ctx, base){tail}'

            new, n_bare = BARE_RE.subn(sub_bare, new)
            n = n_cond + n_bare
            if not n:
                continue

            print(f'{os.path.relpath(f, ROOT)}: {n} site(s)'
                  + (f' ({n_cond} conditional, {n_bare} unconditional)'
                     if n_cond or n_bare else ''))
            total += n
            if args.check:
                continue
            with open(f, 'w', encoding='utf-8', newline='') as fh:
                fh.write(new)

        for h, r in sorted(returns.items()):
            print(f'   fc3_label_{h}: caller returns afterwards = {r}')

    print(f'\nfix_cross_file_branch_calls: {total} site(s)'
          + (' (check only)' if args.check else ' rewritten'))
    return 0


if __name__ == '__main__':
    sys.exit(main())