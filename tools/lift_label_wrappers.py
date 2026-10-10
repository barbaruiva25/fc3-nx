#!/usr/bin/env python3
"""Moves the wrappers that tools/fix_cross_file_labels.py created to the top of their file, at file scope.

THE PROBLEM (Far Cry 3, sub_83493D58's epilogue)

    fc3_recomp.66.cpp:24981:68: error: function definition is not allowed here
    fc3_recomp.66.cpp:24607:24: error: use of undeclared label 'fc3_label_83494048'

The wrapper was inserted where the `loc_83494044:` line was, which is INSIDE `DEFINE_REX_FUNC(sub_83493D58) { ... }`.
A nested function definition is a syntax error in C++, and the branches that reach the wrapper (in other functions in
the same file) come before the declaration.

THE FIX: lift each wrapper out of the function body and place it right after the `#include` block, before the first
`DEFINE_REX_FUNC`. The declaration stays at the top too (it is already there); this makes the definition visible to
every caller in the file and puts it at namespace scope.

Idempotent: a wrapper already at column 0 before the first DEFINE_REX_FUNC is left alone.

    python3 tools/lift_label_wrappers.py
    python3 tools/lift_label_wrappers.py --check
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'app', 'generated')

WRAPPER_START = re.compile(r'^void\s+(fc3_label_[0-9A-Fa-f]+)\s*\(PPCContext& __restrict ctx, uint8_t\* base\)\s*\{\s*$')
FUNC_START = re.compile(r'^DEFINE_REX_FUNC\(')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gen', action='append', default=[])
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    trees = args.gen or [os.path.join(GEN, n) for n in sorted(os.listdir(GEN))
                         if os.path.isdir(os.path.join(GEN, n))]

    lifted_total = 0
    for tree in trees:
        files = [os.path.join(tree, n) for n in sorted(os.listdir(tree))
                 if n.startswith('fc3_recomp.') and n.endswith('.cpp')]
        for f in files:
            with open(f, encoding='utf-8') as fh:
                lines = fh.readlines()

            # Where the first DEFINE_REX_FUNC starts: wrappers must go above it.
            first_func = None
            for i, line in enumerate(lines):
                if FUNC_START.match(line):
                    first_func = i
                    break
            if first_func is None:
                continue

            # Find wrapper definitions that are nested (their closing brace is the function's, i.e. they are inside).
            lifts = []
            i = 0
            while i < len(lines):
                m = WRAPPER_START.match(lines[i])
                if m:
                    # walk to the matching close brace at column 0
                    j = i + 1
                    depth = 1
                    while j < len(lines):
                        if lines[j].rstrip() == '}':
                            depth -= 1
                            if depth == 0:
                                break
                        j += 1
                    block = lines[i:j + 1]
                    # normalize indentation to column 0
                    fixed = [re.sub(r'^\t+', '\t', b.rstrip('\n')) + '\n' for b in block]
                    lifts.append((i, j, fixed, m.group(1)))
                    i = j + 1
                else:
                    i += 1

            if not lifts:
                continue

            rel = os.path.relpath(f, ROOT)
            already_top = all(l[0] < first_func for l in lifts)
            print(f'{rel}: {len(lifts)} wrapper(s)' + (' (already at top)' if already_top else ' to lift'))

            if args.check or already_top:
                continue

            # Remove them (from the bottom up so line numbers stay valid), then re-insert after the last #include.
            for start, end, _fixed, _name in sorted(lifts, reverse=True):
                del lines[start:end + 1]

            # Any goto inside a lifted wrapper must stay inside it; if the wrapper's body branched to another
            # wrapper, that is a call, already rewritten. Nothing to do here.
            bodies = [''.join(b) for _s, _e, b, _n in lifts]

            last_include = 0
            for m in re.finditer(r'^#include .*$', ''.join(lines), re.M):
                last_include = m.end()
            head = ''.join(lines)[:last_include]
            tail = ''.join(lines)[last_include:]

            insert = '\n' + ''.join(bodies)
            new_text = head + insert + tail
            with open(f, 'w', encoding='utf-8', newline='') as fh:
                fh.write(new_text)
            lifted_total += len(lifts)

    print(f'\nlift_label_wrappers: {lifted_total} wrapper(s) lifted'
          + (' (check only)' if args.check else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())