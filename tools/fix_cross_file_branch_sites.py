#!/usr/bin/env python3
"""Rewrites the branch sites of a cross-file jump once tools/fix_cross_file_labels.py has wrapped the block.

Kept separate because the two halves have to happen in order and the wrapper step is what makes the block stop being
a bare `label:` (so a second pass of the wrapper tool finds nothing to do and reports 0, which looks like failure):

  1. fix_cross_file_labels.py    turns `loc_XXXXXXXX:` + its body into `void fc3_label_XXXXXXXX(ctx, base) { ... }`
                                  in the file that owns the block;
  2. this script                  rewrites `goto loc_XXXXXXXX;` into `goto fc3_label_XXXXXXXX(ctx, base);` and adds the
                                  extern declarations to the file that branches.

Re-running is safe: a site already rewritten is not matched again, and the declarations are added only if absent.

    python3 tools/fix_cross_file_branch_sites.py
    python3 tools/fix_cross_file_branch_sites.py --check
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'app', 'generated')

WRAPPER_RE = re.compile(r'^(?:extern "C" )?void\s+fc3_label_([0-9A-Fa-f]+)\s*\(PPCContext&', re.M)


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
        if not files:
            continue

        wrappers = set()
        for f in files:
            with open(f, encoding='utf-8', errors='replace') as fh:
                wrappers.update(m.group(1).upper() for m in WRAPPER_RE.finditer(fh.read()))

        for f in files:
            with open(f, encoding='utf-8') as fh:
                text = fh.read()

            # Labels this file branches to, whether or not the branch still says `goto loc_...`: a file rewritten by
            # an earlier run has `goto fc3_label_XXXXXXXX(ctx, base);` already, and only needs the declaration. The
            # wrappers are global to the tree, so "is there a wrapper for this hex anywhere" is the right question,
            # not "does this file define one".
            needed = set()
            for m in re.finditer(r'\bgoto\s+loc_([0-9A-Fa-f]+)\s*;', text):
                if m.group(1).upper() in wrappers:
                    needed.add(m.group(1).upper())
            for m in re.finditer(r'\bgoto\s+fc3_label_([0-9A-Fa-f]+)\s*\(', text):
                needed.add(m.group(1).upper())
            if not needed:
                continue

            ordered = sorted(needed)
            sites = sum(len(re.findall(r'\bgoto\s+loc_' + h + r'\s*;', text, re.I)) for h in ordered)
            print(f'{os.path.relpath(f, ROOT)}: {sites} branch site(s) -> '
                  + ', '.join(f'fc3_label_{h}' for h in ordered))
            total += sites
            if args.check:
                continue

            for h in ordered:
                text = re.sub(r'\bgoto\s+loc_' + h + r'\s*;',
                              f'goto fc3_label_{h}(ctx, base);', text, flags=re.I)

            missing = []
            head = text.split('goto fc3_label')[0] if 'goto fc3_label' in text else text
            for h in ordered:
                if f'fc3_label_{h}(' not in head:
                    missing.append(f'void fc3_label_{h}(PPCContext& __restrict, uint8_t*);')
            if missing:
                last = 0
                for m in re.finditer(r'^#include .*$', text, re.M):
                    last = m.end()
                text = (text[:last]
                        + '\n\n// Shared epilogue owned by another generated function. The guest branches into it with a\n'
                        + '// plain `b`, which C++ cannot express across translation units, so tools/'
                          'fix_cross_file_labels.py\n'
                        + '// wrapped the block in a function and these are calls to it. The guest instructions are unchanged.\n'
                        + '\n'.join(missing) + '\n'
                        + text[last:])

            with open(f, 'w', encoding='utf-8', newline='') as fh:
                fh.write(text)

    print(f'\nfix_cross_file_branch_sites: {total} branch site(s)'
          + (' (check only)' if args.check else ' rewritten'))
    return 0


if __name__ == '__main__':
    sys.exit(main())