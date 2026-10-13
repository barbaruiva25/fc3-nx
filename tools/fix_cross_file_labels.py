#!/usr/bin/env python3
"""Makes a cross-file jump into a shared epilogue a call to a function standing in for it.

THE PROBLEM (Far Cry 3: sub_83493B70 branches into sub_83493D58's epilogue)

    fc3_recomp.326.cpp:26796:24: error: use of undeclared label 'loc_83494048'

Both functions are real and generated, but in different files:

    fc3_recomp.66.cpp   DEFINE_REX_FUNC(sub_83493D58) { ... loc_83494044: loc_83494048: ...epilogue... }
    fc3_recomp.326.cpp  DEFINE_REX_FUNC(sub_83493B70) { ... goto loc_83494048; ... }

0x83494044/0x83494048 are the epilogue of sub_83493D58: store r19, pop the frame, restore f30/f31,
__restgprlr_19, return. On the PowerPC a `b` into a shared epilogue is normal and the compiler lays it out that way.
C++ cannot jump into another translation unit's block, so the goto has no label to bind to.

THE FIX: the block becomes a function, the goto becomes a call.

    in the defining file:      void fc3_label_loc_83494044() { <body> }
                              void fc3_label_loc_83494048() { <body> return; }   // the epilogue ends by
                                                                                 // returning, so it returns here
    in the branching file:     extern "C" void fc3_label_loc_83494048();
                              ... goto fc3_label_loc_83494048();

This is exact, not an approximation: the block's instructions, order and registers are untouched. The only difference is
that the caller does a call/return instead of a jump, which the compiler inlines (the functions are tiny and in the
same binary), and the epilogue's own `return` becomes the return of the wrapper.

A label defined in the same file is left alone: those bind normally.
A label that falls through into the code after it (rather than ending in a branch) is NOT converted - wrapping it would
change what executes next for the code above the label.

Usage:
    python3 tools/fix_cross_file_labels.py            # apply
    python3 tools/fix_cross_file_labels.py --check    # report only
    python3 tools/fix_cross_file_labels.py --gen app/generated/default
"""

import argparse
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'app', 'generated')

LABEL_RE = re.compile(r'^([ \t]*)(loc_([0-9A-Fa-f]+)):[ \t]*$')
GOTO_RE = re.compile(r'\bgoto\s+(loc_([0-9A-Fa-f]+))\s*;')
FUNC_NAME = 'fc3_label_{}'


def wrapper_name(label):
    return FUNC_NAME.format(label)


def collect(path):
    defs, uses = set(), set()
    with open(path, encoding='utf-8', errors='replace') as fh:
        # rstrip() with no argument, not rstrip('\n'): the generated files have CRLF line endings, and rstrip('\n')
        # leaves the '\r', which LABEL_RE's [ \t]*$ then refuses. That made every label look undefined and the tool
        # reported "0 branches" on a tree that has 444 of them.
        for line in fh:
            s = line.rstrip()
            m = LABEL_RE.match(s)
            if m:
                # Group 3 is the hex address: group 1 is the indent, group 2 the whole 'loc_XXXXXXXX'.
                # Using group 2 stored 'loc_83494044' (with the prefix) where the goto side stores bare hex, so no
                # label ever matched a branch and the tool reported zero.
                defs.add(m.group(3))
            m = GOTO_RE.search(s)
            if m:
                uses.add(m.group(2))
    return defs, uses


def wrap_block(path, label, project):
    """Turns `label:` plus its block into a function. Returns True when it did."""
    with open(path, encoding='utf-8') as fh:
        lines = fh.readlines()

    start = None
    for i, line in enumerate(lines):
        m = LABEL_RE.match(line.rstrip())
        if m and m.group(3) == label:
            start = i
            break
    if start is None:
        return False
    if any(wrapper_name(label) in l for l in lines[max(0, start - 4):start]):
        return False  # already wrapped

    # Find where the block ends: the next label at column 0, or the closing brace of the function at column 0.
    # Generated labels sit at column 0; code is indented one tab.
    end = len(lines)
    for i in range(start + 1, len(lines)):
        stripped = lines[i].rstrip('\n')
        if LABEL_RE.match(stripped) or stripped == '}':
            end = i
            break
    body = lines[start + 1:end]

    # A block that ends by branching must not fall through into the wrapper's `return` twice; if it already returns or
    # jumps away on every path, leave it alone. A plain fall-through (the epilogue case) needs the explicit return.
    last_meaningful = [l for l in body if l.strip() and not l.strip().startswith('//')]
    ends_with_branch = bool(last_meaningful) and re.search(
        r'\b(goto|return)\b', last_meaningful[-1]) is not None

    pad = '\t'
    out = lines[:start]
    # extern "C": the forward declarations this tool writes (and the ones lift writes at the top of
    # the branching files) use C linkage. A C++-linkage definition mangles the name and the link
    # fails with "undefined symbol: fc3_label_X" (fc3-nx, 2026-10-12).
    out.append(f'extern "C" void {wrapper_name(label)}(PPCContext& __restrict ctx, uint8_t* base) {{\n')
    out.extend(body)
    if not ends_with_branch:
        out.append(f'{pad}return;\n')
    out.append('}\n')
    out.extend(lines[end:])

    with open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.writelines(out)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gen', action='append', default=[])
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    trees = args.gen or [os.path.join(GEN, n) for n in sorted(os.listdir(GEN))
                         if os.path.isdir(os.path.join(GEN, n))]

    total_labels = total_sites = 0

    for tree in trees:
        files = [os.path.join(tree, n) for n in sorted(os.listdir(tree))
                 if n.startswith('fc3_recomp.') and n.endswith('.cpp')]
        if not files:
            continue

        def_index = defaultdict(list)
        for f in files:
            defs, _ = collect(f)
            for label in defs:
                def_index[label].append(f)

        remote = defaultdict(list)  # file -> labels it branches to in another file
        for f in files:
            _, uses = collect(f)
            for label in uses:
                hosts = def_index.get(label, [])
                if len(hosts) == 1 and hosts[0] != f:
                    remote[f].append(label)

        for f in sorted(remote):
            labels = sorted(remote[f])
            print(f'{os.path.relpath(f, ROOT)}: {len(labels)} branch(es) -> '
                  + ', '.join(f'{label} (in {os.path.basename(def_index[label][0])})' for label in labels))
            total_labels += len(labels)
            if args.check:
                continue

            with open(f, encoding='utf-8') as fh:
                text = fh.read()
            sites = 0
            for label in labels:
                # `label` is the bare hex (group 3 of LABEL_RE / group 2 of GOTO_RE); the text says `goto loc_<hex>;`,
                # so the pattern has to spell the prefix out. Passing the bare hex matched nothing, which is why the
                # first run reported "wrapped 2 label(s), 0 branch site(s) rewritten" and left the file uncompilable.
                text, n = re.subn(r'\bgoto\s+loc_' + re.escape(label) + r'\s*;',
                                  f'goto {wrapper_name(label)}(ctx, base);', text)
                sites += n
            last_include = 0
            for m in re.finditer(r'^#include .*$', text, re.M):
                last_include = m.end()
            decls = '\n'.join(f'extern "C" void {wrapper_name(label)}(PPCContext& __restrict, uint8_t*);'
                              for label in labels)
            text = (text[:last_include]
                    + '\n\n// Jumps into a block that belongs to another generated function (shared epilogue).\n'
                    + '// C++ cannot do that across translation units, so each is a call to the wrapper that\n'
                    + '// tools/fix_cross_file_labels.py put around that block; the guest code itself is untouched.\n'
                    + decls + '\n'
                    + text[last_include:])
            with open(f, 'w', encoding='utf-8', newline='') as fh:
                fh.write(text)
            total_sites += sites
            print(f'   rewrote {sites} branch site(s)')

            for label in labels:
                if wrap_block(def_index[label][0], label, 'fc3'):
                    print(f'   wrapped {label} in {os.path.basename(def_index[label][0])}')

    if args.check:
        print(f'\nfix_cross_file_labels: {total_labels} branch(es) into another file (check only)')
    else:
        print(f'\nfix_cross_file_labels: {total_labels} label(s), {total_sites} branch site(s) rewritten')
    return 0


if __name__ == '__main__':
    sys.exit(main())