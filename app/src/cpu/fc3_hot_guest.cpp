// Far Cry 3 - native replacements of hot guest functions (CPU enhancements fc3_cpu_native_*; from
// masseffect-nx's me_hot_guest.cpp).
//
// Every hook replaces one recompiled function by a native version (src/cpu/hot/n_<addr>.h) and checks itself: for the
// first fc3_hot_guard_calls calls of each thread (every call with fc3_cpu_verify) and every fc3_hot_guard_period-th call
// afterwards, the native version runs on a copy of the registers with the guest ranges it writes snapshotted, the
// memory is rolled back, the original (__imp__sub_X) runs for real, and registers, written ranges and the FPU mode are
// compared. A difference logs "[hot] DIFFERENCE ..." and switches that hook off for the rest of the run (the original
// already produced the correct state). A hook also stays off when the loaded game code is not byte for byte the code
// the native was written from.
//
// The profile that chose them: the PC profile of the game thread with the GPU wait asleep (docs/enhancements.md).
// WHY EXACT: the CRT natives reproduce the routines' memory effect and return register (n_827F05C0.h etc. say why);
//   the others are localized copies of the recompiled functions themselves (tools/localize_native.py).
// RISK: a native that differs only on inputs the guard did not see. KEY: each fc3_cpu_native_* (fc3_cpu_enhancements).

// The generated code's macros and helpers (the localized copies are made of generated code) ...
#include "../../generated/default/fc3_pch.h"

// ... with plain guest memory: the recompiled code's accesses are volatile, which keeps GCC from pairing and
// scheduling them; a native replacement does not need that (a racing write from another thread is a race either way).
#undef REX_LOAD_U8
#undef REX_LOAD_U16
#undef REX_LOAD_U32
#undef REX_LOAD_U64
#undef REX_STORE_U8
#undef REX_STORE_U16
#undef REX_STORE_U32
#undef REX_STORE_U64
#define REX_LOAD_U8(x) (*(u8*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
#define REX_LOAD_U16(x) __builtin_bswap16(*(u16*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
#define REX_LOAD_U32(x) __builtin_bswap32(*(u32*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
#define REX_LOAD_U64(x) __builtin_bswap64(*(u64*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
#define REX_STORE_U8(x, y) (*(u8*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)) = (y))
#define REX_STORE_U16(x, y) (*(u16*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)) = __builtin_bswap16(y))
#define REX_STORE_U32(x, y) (*(u32*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)) = __builtin_bswap32(y))
#define REX_STORE_U64(x, y) (*(u64*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)) = __builtin_bswap64(y))

#include "fc3_hot_guest.h"
#include "fc3_hot_copies.h"

#include <algorithm>
#include <string>
#include <vector>

#include <fmt/format.h>

#include <rex/cvar.h>
#include <rex/logging.h>


// No hot functions registered yet: every entry above pointed at a Sonic Adventure 2 guest function (the Ninja
// matrix library, the CRT helpers, the chunk-model vertex loaders), and Far Cry 3 has none of those addresses.
// The mechanism is intact: drop the addresses in app/src/cpu/hot/localized.txt (tools/localize_native.py
// regenerates their code into app/generated/hot/), or write a native by hand in src/cpu/hot/n_<addr>.h, then
// register it here with fc3_HOT_HOOK, its writes, its comparison mode and the FNV-1a hash of the guest code it was
// written from. Until then every guest function runs its translated code, which is correct, just not yet fast.
// The addresses to use come from the console profile (guia, capitulo 9.3), not from the other port.
