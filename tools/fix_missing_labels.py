#!/usr/bin/env python3
"""Reports branch targets the code generator emitted a `goto` for but never wrote the `loc_...:` label of.

    error: use of undeclared label 'loc_83494048'

The generator collects the labels a function's blocks branch to (function_graph.cpp, "Labels": every `b`/`bc`
target inside a block) and emits `loc_<addr>:` only where a block actually starts. When a branch targets an address
no block covers, the goto is written and the label is not.

This tool only *reports*. It does not repair, because the generated `.cpp` does not carry each instruction's guest
address (the comments hold the mnemonic, not the address), so the position of the missing label cannot be
recovered from the generated code alone: inserting it anywhere would move the guest's control flow.

The fix belongs upstream, in the manifest: `codegen.partition.json` says which function an address belongs to, and
if that function is missing from the generated tree, it is a gap - a function the Discover phase never made - and
belongs in app/overrides.toml with its evidence (guia, capitulo 3.2). Run this after every codegen:

    python3 tools/fix_missing_labels.py            # report, with the function each address belongs to
    python3 tools/fix_missing_labels.py --quiet    # only print when something is missing

Exit code 0 either way, so it can always run.
"""

import argparse
import bisect
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'app', 'generated')

GOTO_RE = re.compile(r'\bgoto\s+(loc_([0-9A-Fa-f]+))\s*;')
LABEL_RE = re.compile(r'^\s*(loc_[0-9A-Fa-f]+):\s*$')
FUNC_RE = re.compile(r'DEFINE_REX_FUNC\(sub_([0-9A-Fa-f]+)\)')


def load_partition(tree):
    """address -> the guest function the generator says covers it (sorted for bisect)."""
    path = os.path.join(tree, 'codegen.partition.json')
    if not os.path.isfile(path):
        return None, None
    with open(path, encoding='utf-8') as fh:
        assignments = json.load(fh)['assignments']
    addrs = sorted(int(k, 16) for k in assignments)
    return addrs, assignments


def owning_function(addrs, addr):
    i = bisect.bisect_right(addrs, addr) - 1
    return addrs[i] if i >= 0 else None


def scan_file(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    targets, declared = set(), set()
    for line in text.splitlines():
        m = GOTO_RE.search(line)
        if m:
            targets.add((m.group(1), int(m.group(2), 16)))
        m = LABEL_RE.match(line)
        if m:
            declared.add(m.group(1))
    return {(name, addr) for name, addr in targets if name not in declared}


def generated_functions(tree):
    found = set()
    for name in os.listdir(tree):
        if name.startswith('fc3_funcs.') and name.endswith('.h'):
            with open(os.path.join(tree, name), encoding='utf-8', errors='replace') as fh:
                for m in FUNC_RE.finditer(fh.read()):
                    found.add(m.group(1).upper())
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gen', action='append', default=[], help='a generated tree (default: every tree)')
    ap.add_argument('--quiet', action='store_true', help='print only when something is missing')
    args = ap.parse_args()

    trees = args.gen or [os.path.join(GEN, n) for n in sorted(os.listdir(GEN))
                         if os.path.isdir(os.path.join(GEN, n))]

    total = 0
    for tree in trees:
        if not os.path.isdir(tree):
            continue
        addrs, _ = load_partition(tree)
        made = generated_functions(tree)
        for name in sorted(os.listdir(tree)):
            if not (name.startswith('fc3_recomp.') and name.endswith('.cpp')):
                continue
            missing = scan_file(os.path.join(tree, name))
            if not missing:
                continue
            total += len(missing)
            print(f'{os.path.relpath(os.path.join(tree, name), ROOT)}:')
            for label, addr in sorted(missing, key=lambda x: x[1]):
                owner = owning_function(addrs, addr) if addrs else None
                if owner is None:
                    print(f'    {label}: no function covers 0x{addr:08X}')
                    continue
                owner_hex = f'{owner:X}'
                state = 'missing from the generated tree (a gap: declare it in app/overrides.toml)' \
                    if owner_hex not in made else 'present but its block was not emitted'
                print(f'    {label}: 0x{addr:08X} inside sub_{owner_hex}, which is {state}')

    if total and not args.quiet:
        print(f'fix_missing_labels: {total} missing label(s)')
    elif total:
        print(f'{total} missing label(s)')
    else:
        print('fix_missing_labels: nothing missing')
    return 0


if __name__ == '__main__':
    sys.exit(main())