// Far Cry 3 - native replacements of hot guest functions: hook dispatch with a self-check guard (from
// masseffect-nx's me_hot_guest.h; see fc3_hot_common.h).
//
// Hot-path cost matters (memcpy is called from ~2,000 places): the Hook object is constant-initialised (no
// function-local static guard: an acquire load per call, measured at ~1.3 % of Mass Effect's main thread on one hook),
// the only per-call shared state is one byte load, and the call counter that decides which calls are checked is
// thread-local.
#pragma once

#include <atomic>
#include <cstdint>
#include <type_traits>

#include <rex/hook.h>

#include "cpu/fc3_enhancements.h"
#include "cpu/fc3_hot_common.h"

namespace fc3::hot {

enum : uint8_t { kUninit = 0, kOff = 1, kOn = 2 };

struct Hook {
  const char* name;
  PPCFunc* orig;
  bool (*native)(PPCContext&, uint8_t*);  // false = declined: nothing was modified, the original must run
  void (*writes)(const PPCContext&, const uint8_t*, Writes&);
  Cmp cmp;
  fc3::enh::Enhancement* key;
  uint32_t code_address;  // the guest code the native was written from (tools/guest_code_hash.py)
  uint32_t code_bytes;
  uint64_t code_hash;
  // Runtime state. Until the first call initialises it the zeros are harmless: kUninit goes to the slow path, and a
  // stale guard_calls/period_mask of 0 on another core only means "check this call".
  std::atomic<uint8_t> state{kUninit};
  uint32_t guard_calls = 0;         // the first N calls of each thread are always checked ...
  uint32_t period_mask = 0;         // ... afterwards every (mask+1)-th call
  std::atomic<bool> failed{false};  // a check found a difference: the original runs from now on
  std::atomic<uint64_t> checks{0};
};

extern ::fc3::enh::Enhancement g_counter_shared;  // fc3_cpu_hook_counter_shared (fc3_hot_guest.cpp)

// First call of a hook (any thread): key, code check, guard settings. Defined in fc3_hot_guest.cpp.
void InitHook(Hook& h, uint8_t* base);

// One guarded call: native on a copy of the registers with the written ranges snapshotted, rollback, original,
// compare. Leaves the state exactly as the original would. Defined in fc3_hot_guest.cpp.
void Check(Hook& h, PPCContext& ctx, uint8_t* base);

// Use counter for the 10 s report: one shared add per 256 calls of a thread.
inline void CountUse(Hook& h, uint32_t c) {
  if ((c & 255) == 0) h.key->Use(256);
}

template <auto Native>
inline bool NativeB(PPCContext& ctx, uint8_t* base) {
  if constexpr (std::is_void_v<decltype(Native(ctx, base))>) {
    Native(ctx, base);
    return true;
  } else {
    return Native(ctx, base);
  }
}

template <auto Native>
inline void DispatchCount(Hook& h, uint32_t c, PPCContext& ctx, uint8_t* base) {
  CountUse(h, c);
  if (c < h.guard_calls || (c & h.period_mask) == 0) [[unlikely]] {
    Check(h, ctx, base);
    return;
  }
  if (!NativeB<Native>(ctx, base)) h.orig(ctx, base);
}

template <auto Native>
inline void Dispatch(Hook& h, uint32_t& n, PPCContext& ctx, uint8_t* base) {
  if (h.failed.load(std::memory_order_relaxed)) [[unlikely]] {
    h.orig(ctx, base);
    return;
  }
  DispatchCount<Native>(h, n++, ctx, base);
}

// fc3_cpu_hook_counter_shared: one counter per hook for all threads (a relaxed load and store, no read-modify-write:
// racing threads may count a call twice, which only moves which calls the guard samples). On the Switch a
// thread_local costs a call to __aarch64_read_tp on every hooked call (memcpy alone comes from ~2,000 call sites).
// The guard then checks the first N calls of the process instead of the first N of each thread.
template <auto Native>
inline void DispatchShared(Hook& h, std::atomic<uint32_t>& n, PPCContext& ctx, uint8_t* base) {
  if (h.failed.load(std::memory_order_relaxed)) [[unlikely]] {
    h.orig(ctx, base);
    return;
  }
  const uint32_t c = n.load(std::memory_order_relaxed);
  n.store(c + 1, std::memory_order_relaxed);
  if ((c & 255) == 0) [[unlikely]] g_counter_shared.Use(256);
  DispatchCount<Native>(h, c, ctx, base);
}


}  // namespace fc3::hot

// KEY: the enhancement key (fc3_cpu_native_*); NS: namespace of the n_*.h header; ADDR: hex address without 0x;
// BYTES / HASH: tools/guest_code_hash.py ADDR; CMP: fc3::hot::Cmp::kReturn or kAll.
#define fc3_HOT_HOOK(ADDR, KEY, DESC, NS, WRITES, CMP, BYTES, HASH)                                            \
  fc3_ENHANCEMENT(g_enh_##ADDR, KEY, fc3::enh::kCpu, true, DESC);                                          \
  REX_EXTERN(__imp__sub_##ADDR);                                                                           \
  REX_HOOK_RAW(sub_##ADDR) {                                                                               \
    static fc3::hot::Hook h{"sub_" #ADDR, &__imp__sub_##ADDR, &fc3::hot::NativeB<&NS::Native>, WRITES, CMP, \
                            &g_enh_##ADDR, 0x##ADDR##u, BYTES, HASH};                                       \
    uint8_t st = h.state.load(std::memory_order_relaxed);                                                  \
    if (st == fc3::hot::kUninit) [[unlikely]] {                                                            \
      fc3::hot::InitHook(h, base);                                                                         \
      st = h.state.load(std::memory_order_relaxed);                                                        \
    }                                                                                                      \
    if (st == fc3::hot::kOn) [[likely]] {                                                                  \
      if (fc3::hot::g_counter_shared.active) [[likely]] {                                                         \
        static std::atomic<uint32_t> n_shared;                                                             \
        fc3::hot::DispatchShared<&NS::Native>(h, n_shared, ctx, base);                                     \
      } else {                                                                                             \
        static thread_local uint32_t n_calls;                                                              \
        fc3::hot::Dispatch<&NS::Native>(h, n_calls, ctx, base);                                            \
      }                                                                                                    \
      return;                                                                                              \
    }                                                                                                      \
    __imp__sub_##ADDR(ctx, base);                                                                          \
  }

// Unguarded: for localized copies of functions that call other functions. The guard cannot run both versions there
// (the callees' side effects would happen twice), so the copy runs on every call once its key and code check pass.
// Exact by construction (tools/localize_native.py); checked end to end on the PC (lockstep capture).
// OFF by default (experimental): a copy writes back and reloads every localized register at each call, so copies that
// make real calls were SLOWER (sasrt-nx PC A/B: game threads +13-18 % CPU per frame with 36 copies on; per function up
// to 2x the samples). Leaves and functions that only call the save/restore helpers got faster.
#define fc3_HOT_HOOK_UNGUARDED(ADDR, KEY, DESC, NS, BYTES, HASH) fc3_HOT_HOOK_COPY(ADDR, KEY, false, DESC, NS, BYTES, HASH)
// The same with the key's default given (round 3: copies with smart sync).
#define fc3_HOT_HOOK_COPY(ADDR, KEY, DEFAULT, DESC, NS, BYTES, HASH)                               \
  fc3_ENHANCEMENT(g_enh_##ADDR, KEY, fc3::enh::kCpu, DEFAULT, DESC);                            \
  REX_EXTERN(__imp__sub_##ADDR);                                                                \
  REX_HOOK_RAW(sub_##ADDR) {                                                                    \
    static std::atomic<uint8_t> state{fc3::hot::kUninit};                                       \
    static std::atomic<uint32_t> n_calls; /* the use report only: a lossy relaxed count, no TLS */ \
    uint8_t st = state.load(std::memory_order_relaxed);                                         \
    if (st == fc3::hot::kUninit) [[unlikely]] {                                                 \
      const bool on = g_enh_##ADDR.active &&                                                    \
                      fc3::enh::GuestCodeMatches(base, 0x##ADDR##u, BYTES, HASH, #KEY);         \
      st = on ? fc3::hot::kOn : fc3::hot::kOff;                                                 \
      state.store(st, std::memory_order_relaxed);                                               \
    }                                                                                           \
    if (st == fc3::hot::kOn) [[likely]] {                                                       \
      const uint32_t c = n_calls.load(std::memory_order_relaxed);                               \
      n_calls.store(c + 1, std::memory_order_relaxed);                                          \
      if ((c & 255) == 0) g_enh_##ADDR.Use(256);                                                \
      NS::Native(ctx, base);                                                                    \
      return;                                                                                   \
    }                                                                                           \
    __imp__sub_##ADDR(ctx, base);                                                               \
  }

// A localized copy of a function the renderer hooks too (src/me/fc3_me_hooks.cpp): a function has one override, so
// there is no REX_HOOK_RAW here; the renderer's hook calls fc3::hot::Copy_ADDR (cpu/fc3_hot_copies.h) where it called
// __imp__sub_ADDR. Unguarded and exact by construction like fc3_HOT_HOOK_COPY. Not in localize_native.py's natives:
// the renderer's hook reads argument registers itself, so a copy that calls this function syncs everything.
#define fc3_COPY_FOR_HOOK(ADDR, KEY, DEFAULT, DESC, NS, BYTES, HASH)                               \
  fc3_ENHANCEMENT(g_enh_##ADDR, KEY, fc3::enh::kCpu, DEFAULT, DESC);                            \
  REX_EXTERN(__imp__sub_##ADDR);                                                                \
  void fc3::hot::Copy_##ADDR(PPCContext& ctx, uint8_t* base) {                                  \
    static std::atomic<uint8_t> state{fc3::hot::kUninit};                                       \
    static std::atomic<uint32_t> n_calls; /* the use report only: a lossy relaxed count, no TLS */ \
    uint8_t st = state.load(std::memory_order_relaxed);                                         \
    if (st == fc3::hot::kUninit) [[unlikely]] {                                                 \
      const bool on = g_enh_##ADDR.active &&                                                    \
                      fc3::enh::GuestCodeMatches(base, 0x##ADDR##u, BYTES, HASH, #KEY);         \
      st = on ? fc3::hot::kOn : fc3::hot::kOff;                                                 \
      state.store(st, std::memory_order_relaxed);                                               \
    }                                                                                           \
    if (st == fc3::hot::kOn) [[likely]] {                                                       \
      const uint32_t c = n_calls.load(std::memory_order_relaxed);                               \
      n_calls.store(c + 1, std::memory_order_relaxed);                                          \
      if ((c & 255) == 0) g_enh_##ADDR.Use(256);                                                \
      NS::Native(ctx, base);                                                                    \
      return;                                                                                   \
    }                                                                                           \
    __imp__sub_##ADDR(ctx, base);                                                               \
  }
