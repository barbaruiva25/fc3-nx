// Temporary boot-debugging hooks: log who calls a function and with which arguments, then call the original.
// Each entry says which crash it is chasing; remove it once the cause is fixed. Empty while no crash needs one.
//
// Pattern (the setjmp/longjmp case of the fourth boot is written up in docs/fc3-notes.md):
//   extern "C" REX_FUNC(__imp__sub_XXXXXXXX);
//   REX_HOOK_RAW(sub_XXXXXXXX) {
//     REXLOG_WARN("[dbg] sub_XXXXXXXX(r3={:08X}) from lr={:08X}", ctx.r3.u32, uint32_t(ctx.lr));
//     __imp__sub_XXXXXXXX(ctx, base);
//   }

#include <atomic>

#include <rex/hook.h>
#include <rex/logging.h>

// ---------------------------------------------------------------------------------------------
// CRASH UNDER INVESTIGATION: out\pc\logs\fc3_002.log onwards (2026-10-10)
//
//   [error] Unhandled guest access violation: read of guest 0x0000013C on thread 0xF8000060
//   [error] Unhandled guest access violation at host PC ... (fc3.exe+0x79E9405)
//
// Six guest threads fault in the same millisecond, all reading exactly 0x13C. Six threads reading one
// address at one instant is not register corruption: it is a single shared value that is still zero.
// 0x13C is offset 316 (0x13C) from a null base.
//
// llvm-symbolizer blames sub_8237E408 (fc3_recomp.347.cpp:319, "lwz r11,316(r28)") because that is the
// nearest preceding symbol in the PDB, but the hooks below show the fault happens several calls deeper:
// sub_8237E408 -> sub_8362B1C0 -> sub_82342460 -> sub_8240B808 -> sub_83611CD0. The symbolizer is wrong,
// not the translation - the generated code is right, the trace below is what actually runs.
//
// The heap the allocator checks against still holds its initial values at the moment of the fault
// ([0xA0000000, 0xFFFFFFFF]), which is the thing worth explaining. Everything else here is scaffolding to
// find where that happens.
// ---------------------------------------------------------------------------------------------

namespace {

// The boot crashes within the first few hundred calls, so a small cap is enough to see the pattern
// and keeps a 6-thread crash loop from filling the log.
constexpr int kMaxLogs = 400;

// One slot per traced function. A flat per-function cap is not enough here: the boot makes several hundred
// calls to sub_83611CD0 before the faulting thread arrives, so the cap is always spent on the noise and the
// last call - the one that crashes - is exactly the one that goes unlogged. The counters are rewound on
// first entry into the faulting function instead, which puts the whole crash window inside the cap.
std::atomic<int> g_callee[16]{};

std::atomic<int> g_entries{0};
std::atomic<int> g_clobbers{0};
std::atomic<int> g_b1c0_calls{0};
std::atomic<int> g_b1c0_changes{0};

// REX_LOAD_U32 lives in the generated PCH, which the app does not include. Same thing by hand: the guest arena
// is big-endian, and on Windows addresses at or above 0xE0000000 are MMIO and get a 0x1000 host offset
// (REX_PHYS_HOST_OFFSET in the PCH). Neither applies to a heap-bound word, but the offset is kept so this
// reads exactly what the callee reads.
inline uint32_t GuestLoad32(uint8_t* base, uint32_t addr) {
  const uint32_t host_off = (addr >= 0xE0000000u) ? 0x1000u : 0u;
  uint32_t v;
  __builtin_memcpy(&v, base + addr + host_off, sizeof(v));
  return __builtin_bswap32(v);
}

// The heap bounds sub_8240B808 compares against: lis r11,-31774 / addi r11,r11,-19200 = 0x83E1B500, and the
// word after it. Plus "lis r11,16384" = 0x40000000, the sentinel that routes a pointer to the error handler.
constexpr uint32_t kHeapMin = 0x83E1B500;
constexpr uint32_t kHeapMax = 0x83E1B504;
constexpr uint32_t kSentinel = 0x40000000;

// sub_8237E408's indirect calls all go through one entry: r28 = 0x83E1A148 (lis r11,-31774 / addi
// r11,r11,-24248), then "lwz r11,316(r28)" loads a function pointer from 0x83E1A284 and "bctrl" calls it.
constexpr uint32_t kCallbackTable = 0x83E1A284;

}  // namespace

// The function the first log line names. Its first entry is the crash point every time, so that is where the
// trace window is rewound; entry and exit also answer whether r28 survives the calls, which is what the
// first two hypotheses about this crash were about.
// The target of the three indirect calls in sub_8237E408, found by following the table it goes through:
//   [0x83E1A284] = 0x83EDCE44  ->  [0x83EDCE44] = 0x82405188  ->  bctrl
// sub_82405188 is a two-instruction thunk ("b 0x82412ee8"), and sub_82412EE8 is the allocator's front door:
// it calls sub_82412D40 first (the heap-lazy-init check) and then either sub_8240D130 or sub_8240B778.
// None of them is on the path: the last traced line before the fault is "OUT sub_8362B1C0", which is a direct
// call further down sub_8237E408. So the fault is between the two - in the code the SDK emits for bctrl
// itself, which is why no hook fires. ctx.last_indirect_target is the SDK's record of what bctrl was about
// to call (set unconditionally, per rex/ppc/context.h), so it names the real target without a hook.
REX_EXTERN(__imp__sub_8237E408);
REX_HOOK_RAW(sub_8237E408) {
  const uint32_t r28_in = ctx.r28.u32;
  const uint32_t lr_in = static_cast<uint32_t>(ctx.lr);
  const uint32_t ind_in = ctx.last_indirect_target;

  const int n = g_entries.fetch_add(1) + 1;
  if (n == 1) {
    for (auto& c : g_callee) {
      c.store(0);
    }
    REXLOG_WARN("[dbg] === trace window reset (first entry into the function the crash log names) ===");
  }
  if (n <= kMaxLogs) {
    REXLOG_WARN("[dbg] sub_8237E408 #{:d} from lr={:08X}: r28={:08X} r31={:08X} r30={:08X} r29={:08X} r3={:08X} "
                "last_indirect_target={:08X}",
                n, lr_in, r28_in, ctx.r31.u32, ctx.r30.u32, ctx.r29.u32, ctx.r3.u32, ind_in);
  }

  __imp__sub_8237E408(ctx, base);

  const uint32_t r28_out = ctx.r28.u32;
  if (r28_out != r28_in) {
    const int c = g_clobbers.fetch_add(1) + 1;
    if (c <= kMaxLogs) {
      REXLOG_WARN("[dbg] sub_8237E408 RETURNED with r28 {:08X} -> {:08X} (clobbered)",
                  r28_in, r28_out);
    }
  }
  return;
}

// sub_8362B1C0 allocates the thread's kernel stack: "mr r28,r4" and no save of r28 anywhere in the function.
// It is the last call that returns before the fault, so its exit registers are the ones the faulting load
// uses: after it returns, sub_8237E408 does "stw r3,12(r30)" and then "lwz r10,300(r31)". r30 and r31 are
// non-volatile, so whatever they hold here is what the caller still believes. r28 survives (its logged value
// comes straight out of the lis/addi pair in the caller), which ruled out the first hypothesis about this
// crash; r30 and r31 are what this hook is here to measure.
REX_EXTERN(__imp__sub_8362B1C0);
REX_HOOK_RAW(sub_8362B1C0) {
  const uint32_t r28_in = ctx.r28.u32;
  const uint32_t r4_in = ctx.r4.u32;

  const int n = g_b1c0_calls.fetch_add(1) + 1;
  if (n <= kMaxLogs) {
    REXLOG_WARN("[dbg] IN  sub_8362B1C0 #{:d}: r4={:08X} r28={:08X} r30={:08X} r31={:08X}", n, r4_in, r28_in,
                ctx.r30.u32, ctx.r31.u32);
  }

  __imp__sub_8362B1C0(ctx, base);
  if (n <= kMaxLogs) {
    REXLOG_WARN("[dbg] OUT sub_8362B1C0 #{:d}: r3={:08X} r28={:08X} r30={:08X} r31={:08X} "
                "(next: [r30+12]={:08X} [r31+300]={:08X})",
                n, ctx.r3.u32, ctx.r28.u32, ctx.r30.u32, ctx.r31.u32, ctx.r30.u32 + 12, ctx.r31.u32 + 300);
  }

  if (ctx.r28.u32 != r28_in) {
    const int c = g_b1c0_changes.fetch_add(1) + 1;
    if (c <= kMaxLogs) {
      REXLOG_WARN("[dbg] sub_8362B1C0 CLOBBERED r28: {:08X} -> {:08X} (r4 was {:08X})",
                  r28_in, ctx.r28.u32, r4_in);
    }
  }
  return;
}

// Traces one callee: logs entry and exit, so a fault that happens inside shows up as an IN line with no
// matching OUT line. The return address is logged too, because reading the caller's C++ cannot say which of
// its several call sites was taken - the flags in r4 select among them - and guessing from the flags got the
// wrong answer twice.
#define FC3_TRACE_CALLEE(fn, slot) FC3_TRACE_CALLEE_AFTER(fn, slot, 0)

#define FC3_TRACE_CALLEE_AFTER(fn, slot, skip)                                     \
  REX_EXTERN(__imp__##fn);                                                         \
  REX_HOOK_RAW(fn) {                                                               \
    const int n = g_callee[slot].fetch_add(1) + 1;                                \
    const bool log = n >= (skip) && n < (skip) + kMaxLogs;                       \
    if (log) {                                                                    \
      REXLOG_WARN("[dbg] IN  {} #{} from lr={:08X} r3={:08X} r4={:08X} r5={:08X}", \
                  #fn, n, static_cast<uint32_t>(ctx.lr), ctx.r3.u32, ctx.r4.u32,   \
                  ctx.r5.u32);                                                     \
    }                                                                              \
    __imp__##fn(ctx, base);                                                        \
    if (log) {                                                                    \
      REXLOG_WARN("[dbg] OUT {} #{} r3={:08X}", #fn, n, ctx.r3.u32);              \
    }                                                                              \
    return;                                                                        \
  }

FC3_TRACE_CALLEE(sub_82342460, 0)   // allocate(size, flags); the flags select one of three paths
FC3_TRACE_CALLEE(sub_82346BF0, 1)
FC3_TRACE_CALLEE(sub_823425D0, 2)
FC3_TRACE_CALLEE(sub_8360DD80, 3)   // memset
FC3_TRACE_CALLEE(sub_8240A080, 13)   // free(), when the pointer is inside the heap
FC3_TRACE_CALLEE(sub_83611CD0, 14)  // the heap's invalid-pointer handler

// The target of the three indirect calls in sub_8237E408, found by following the table it goes through:
//   [0x83E1A284] = 0x83EDCE44  ->  [0x83EDCE44] = 0x82405188  ->  bctrl
// sub_82405188 is a two-instruction thunk ("b 0x82412ee8"), and sub_82412EE8 is the allocator's front door:
// it calls sub_82412D40 first (the heap-lazy-init check) and then either sub_8240D130 or sub_8240B778.
// All four are traced, because "every traced function returned" pointed at one of them.
FC3_TRACE_CALLEE(sub_82405188, 8)
FC3_TRACE_CALLEE(sub_82412EE8, 9)
FC3_TRACE_CALLEE(sub_82412D40, 10)
FC3_TRACE_CALLEE(sub_8240D130, 11)
FC3_TRACE_CALLEE(sub_8240B778, 12)
FC3_TRACE_CALLEE(sub_824053B8, 15)

// sub_83611CD0(ptr) with ptr != 0 goes to sub_82346BE0 then sub_82344988(0, 0, ptr). If the last argument
// turns out to be a format string, the hook below prints what the allocator was complaining about.
FC3_TRACE_CALLEE(sub_82346BE0, 4)
FC3_TRACE_CALLEE(sub_82344988, 5)
FC3_TRACE_CALLEE(sub_836148C8, 6)
FC3_TRACE_CALLEE(sub_83611EA0, 7)

// sub_8240B808 is the free(). Reading its C++ showed four outcomes and none of them touches 0x13C, so the
// trace reads the same two words the callee is about to read and prints which branch actually runs.
REX_EXTERN(__imp__sub_8240B808);
REX_HOOK_RAW(sub_8240B808) {
  const int n = g_callee[12].fetch_add(1) + 1;
  if (n <= kMaxLogs) {
    const uint32_t ptr = ctx.r3.u32;
    const uint32_t lo = GuestLoad32(base, kHeapMin);
    const uint32_t hi = GuestLoad32(base, kHeapMax);
    const char* branch = "?";
    if (ptr < lo || ptr > hi) {
      branch = (ptr >= kSentinel) ? "-> sub_83611CD0" : "-> lwz r3,-16(ptr); ret";
    } else {
      branch = "-> sub_8240A080; ret";
    }
    REXLOG_WARN("[dbg] sub_8240B808 #{} ptr={:08X} heap=[{:08X},{:08X}] {} (r4={:08X} r5={:08X})",
                n, ptr, lo, hi, branch, ctx.r4.u32, ctx.r5.u32);
  }
  __imp__sub_8240B808(ctx, base);
  if (n <= kMaxLogs) {
    REXLOG_WARN("[dbg] OUT sub_8240B808 #{} r3={:08X}", n, ctx.r3.u32);
  }
  return;
}

// ---------------------------------------------------------------------------------------------
// WHERE r28 DIES (2026-10-10)
//
// The faulting instruction was disassembled instead of symbolised, because the previous note above says the
// symbolizer is wrong. It is not. At fc3.exe+0x79E9405 the machine code is:
//
//   movl 0xe0(%rdi), %eax     ; eax = ctx.r28.u32      (r28 sits at 0xE0 of PPCContext)
//   movl $0x13c, %ecx
//   addl %ecx, %eax           ; eax = r28 + 316
//   leaq (%rsi,%rax), %rcx    ; guest base + that
//   cmpl $0xe0000000, %eax
//   shll $0xc, %edx
//   movl (%rdx,%rcx), %eax    ; <-- the fault, guest 0x13C means r28 == 0
//
// That is the ReXGlue guest-load sequence for "lwz r11,316(r28)" (fc3_recomp.347.cpp:319), so the fault is
// where the generated code says it is and r28 is exactly zero.
//
// The open question is only which call destroys it. The body's candidates are sub_8362B0E0, sub_8362B1C0
// (it does "mr r28,r4" -> 0x8237E168, not zero) and sub_8362B300, which is a two-line thunk
// ("b 0x8363ce50") onto sub_8363CE50 - a routine with no prologue that copies 128 vector registers and does
// "ld r28,264(r3)" before tail-branching into KeSetCurrentStackPointers.
//
// Answered by the hooks below (fc3_004.log):
//
//   IN  sub_8363CE50 #1 r28=83E1A148 r3=40007730 [r3+264]=00000000
//   OUT sub_8363CE50 #1 r28=00000000  <<< DESTROYED
//
// sub_8363CE50 is the kernel thread switch: "std r28,264(r5)" saves the outgoing context's r28 into the
// thread that owns this PCR and "ld r28,264(r3)" loads the incoming one's. r3 is the context sub_8362B1C0
// just built, so its +264 is zero - correct, the thread never ran. On the console the caller never reads
// r28 again, because the export that ends the routine does not return: the thread is dispatched.
// ReXGlue's KeSetCurrentStackPointers returns, so sub_8237E408 walks back into its loop with r28 = 0.
//
// WORKAROUND, not the fix. Keeping the non-volatile set across the call makes the return look to the guest
// like the branch it was, and the boot gets past the fault. The real fix is to teach the codegen that this
// export does not return, so the tail call stops being a call - see docs/fc3/DIAGNOSTICO-BOOT-0x13C.md.
// ---------------------------------------------------------------------------------------------
REX_EXTERN(__imp__sub_8363CE50);
REX_HOOK_RAW(sub_8363CE50) {
  const int n = g_b1c0_changes.fetch_add(1) + 1;
  if (n <= 40) {
    REXLOG_WARN("[dbg] IN  sub_8363CE50 #{} r28={:08X} r3={:08X} [r3+264]={:08X}", n, ctx.r28.u32,
                ctx.r3.u32, GuestLoad32(base, ctx.r3.u32 + 264));
  }

  const PPCRegister keep[18] = {ctx.r14, ctx.r15, ctx.r16, ctx.r17, ctx.r18, ctx.r19, ctx.r20, ctx.r21,
                                ctx.r22, ctx.r23, ctx.r24, ctx.r25, ctx.r26, ctx.r27, ctx.r28, ctx.r29,
                                ctx.r30, ctx.r31};
  __imp__sub_8363CE50(ctx, base);
  for (int i = 0; i < 18; i++) {
    (&ctx.r14)[i] = keep[i];
  }

  if (n <= 40) {
    REXLOG_WARN("[dbg] OUT sub_8363CE50 #{} r28={:08X} (kept)", n, ctx.r28.u32);
  }
  return;
}

// ---------------------------------------------------------------------------------------------
// SWITCH CRASH: sub_8365D018 (2026-10-12)
//
// On Switch the game dies writing [r31+..] in sub_8365D018 (guest heap, uncommitted page).
// This hook answers whether the PC build even reaches it, and with which r3/r4. If the PC never
// calls it, the Switch diverged before; if it does with the same shape, the divergence is in the
// Switch commit path.
// ---------------------------------------------------------------------------------------------
REX_EXTERN(__imp__sub_8365D018);
REX_HOOK_RAW(sub_8365D018) {
  const int n = g_b1c0_calls.fetch_add(1) + 1;
  if (n <= 12) {
    REXLOG_WARN("[dbg] IN  sub_8365D018 #{} r3={:08X} r4={:08X} lr={:08X}", n, ctx.r3.u32,
                ctx.r4.u32, static_cast<uint32_t>(ctx.lr));
  }
  __imp__sub_8365D018(ctx, base);
  if (n <= 12) {
    REXLOG_WARN("[dbg] OUT sub_8365D018 #{} r3={:08X}", n, ctx.r3.u32);
  }
  return;
}

// (XamShowDirtyDiscErrorUI hook removido: REX_HOOK_RAW so atua em funcoes do guest, nao em exports
// do kernel. O chamador e registrado direto em sdk/src/kernel/xam/am_ui.cpp como [dirtycaller].)

// A flag global [0x83F26860] decide o dirty-disc (sub_82B33DD8: byte 0 -> suja). O escritor e
// sub_82B34020 (stb r30,26720(r9), r30 = r5 do chamador) e o unico chamador passa r5 = 1. Estes dois
// hooks dizem se o escritor roda e com que r5, e que valor o leitor ve.
REX_EXTERN(__imp__sub_82B34020);
REX_HOOK_RAW(sub_82B34020) {
  REXLOG_WARN("[dbg] WRITEFLAG r5={:08X} r3={:08X} r4={:08X} lr={:08X}", ctx.r5.u32, ctx.r3.u32,
              ctx.r4.u32, static_cast<uint32_t>(ctx.lr));
  __imp__sub_82B34020(ctx, base);
  return;
}

REX_EXTERN(__imp__sub_82B33DD8);
REX_HOOK_RAW(sub_82B33DD8) {
  REXLOG_WARN("[dbg] READFLAG r3={:08X} lr={:08X}", ctx.r3.u32, static_cast<uint32_t>(ctx.lr));
  __imp__sub_82B33DD8(ctx, base);
  return;
}

// Dirty-disc path 2 (the one the PC actually takes): sub_8241BBF0 shows the UI unconditionally
// when called (both its branches reach sub_8362CD00), so the caller IS the error. Three callers exist;
// this names which one and with what args.
REX_EXTERN(__imp__sub_8241BBF0);
REX_HOOK_RAW(sub_8241BBF0) {
  // r3 is a title/message string in the image (e.g. 0x8200EDD8 from sub_8241BD28, which formats the
  // detail into its own frame first). Byte loads are endian-neutral: copy straight from the arena.
  // The detail string: sub_8241BD28 did stwu r1,-352 before calling, and formatted into [r1+80] of
  // its own frame, so here it is at [[r1+432]].
  auto read_guest_str = [&](uint32_t addr, char* dst, size_t cap, bool image_only) {
    if (image_only && (addr < 0x82000000u || addr >= 0x84000000u)) return;
    for (size_t i = 0; i < cap - 1; ++i) {
      const uint32_t a = addr + uint32_t(i);
      const uint32_t host_off = a + ((a >= 0xE0000000u) ? 0x1000u : 0u);
      const char c = reinterpret_cast<const char*>(base)[host_off];
      dst[i] = c;
      if (!c) break;
    }
  };
  char title[128] = {};
  read_guest_str(ctx.r3.u32, title, sizeof(title), true);
  // Detail: the hook runs BEFORE sub_8241BBF0's own prologue, so ctx.r1 is still the CALLER's
  // (sub_8241BD28's) r1, and sub_8360ED78 sprintf'd into [r1+80] of that same frame. Inline text.
  char detail[256] = {};
  read_guest_str(ctx.r1.u32 + 80u, detail, sizeof(detail), false);
  REXLOG_WARN("[dbg] IN  sub8241BBF0 r3={:08X} r4={:08X} lr={:08X} title='{}' detail='{}'", ctx.r3.u32,
              ctx.r4.u32, static_cast<uint32_t>(ctx.lr), title, detail);
  __imp__sub_8241BBF0(ctx, base);
  return;
}

// The detail formatter behind the dirty-disc message: sub_8360ED78(dest, fmt, arg). Log the format
// string (image) and what landed in dest.
REX_EXTERN(__imp__sub_8360ED78);
REX_HOOK_RAW(sub_8360ED78) {
  const uint32_t dest = ctx.r3.u32;
  const uint32_t fmt = ctx.r4.u32;
  auto rdstr = [&](uint32_t addr, char* dst, size_t cap) {
    if (addr < 0x82000000u || addr >= 0x84000000u) return;
    for (size_t i = 0; i < cap - 1; ++i) {
      const uint32_t a = addr + uint32_t(i);
      const char c = reinterpret_cast<const char*>(base)[a];
      dst[i] = c;
      if (!c) break;
    }
  };
  char fmtstr[160] = {};
  rdstr(fmt, fmtstr, sizeof(fmtstr));
  const int n = g_clobbers.fetch_add(1) + 1;
  if (n <= 8) {
    REXLOG_WARN("[dbg] IN  fmt8360ED78 #{} dest={:08X} fmt={:08X}('{:.100}') r5={:08X}", n, dest, fmt,
                fmtstr, ctx.r5.u32);
  }
  __imp__sub_8360ED78(ctx, base);
  if (n <= 8) {
    // Dest is caller stack (mapped): read back what was formatted.
    char out[192] = {};
    for (size_t i = 0; i < sizeof(out) - 1; ++i) {
      const uint32_t a = dest + uint32_t(i);
      const char c = reinterpret_cast<const char*>(base)[a];
      out[i] = c;
      if (!c) break;
    }
    REXLOG_WARN("[dbg] OUT fmt8360ED78 #{} dest='{}' r3={:08X}", n, out, ctx.r3.u32);
  }
  return;
}

// What sub_83658240 writes to its out-param [r8]. sub_8241BBF0 shows dirty-disc when [r1+80] is 0
// after this call; the first thing the callee does is zero it, so the question is whether anything
// writes it back before returning.
REX_EXTERN(__imp__sub_83658240);
REX_HOOK_RAW(sub_83658240) {
  const uint32_t out = ctx.r8.u32;
  const int n = g_clobbers.fetch_add(1) + 1;
  if (n <= 12) {
    REXLOG_WARN("[dbg] IN  sub83658240 #{} r3={:08X} r4={:08X} r6={:08X} out=[{:08X}] lr={:08X}", n,
                ctx.r3.u32, ctx.r4.u32, ctx.r6.u32, out, static_cast<uint32_t>(ctx.lr));
  }
  __imp__sub_83658240(ctx, base);
  if (n <= 12) {
    REXLOG_WARN("[dbg] OUT sub83658240 #{} [out]={:08X} r3={:08X}", n, GuestLoad32(base, out),
                ctx.r3.u32);
  }
  return;
}