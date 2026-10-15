// Windows: logs fatal host exceptions that the SDK does not report (illegal instruction from a __builtin_trap in the
// generated code, divide by zero, stack overflow, ...) with the module and offset, so the crash can be symbolized
// afterwards: llvm-symbolizer --obj=fc3.exe 0x<0x140000000 + offset>. Access violations are left alone: the SDK
// handles those itself (guest memory, MMIO) and reports the unhandled ones.

#if defined(_WIN32)

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstring>

#include <rex/logging.h>
#include <rex/logging/api.h>
#include <rex/system/thread_state.h>

namespace {

// Guest 0xF90CAA20[0] becomes 0x04020000 (raw host bytes 04 02 00 00) between its
// allocation and the vec85378 loop (fc3_048.log, deterministic across runs). A targeted
// write watch finds the writer: protect the host page NOACCESS from a hook, catch the
// fault here (re-added to the front of the chain at arm time, ahead of the SDK handler),
// log the writer, unprotect, and re-arm until the dword turns bad.
constexpr uint32_t kWatchGuest = 0xF90CAA20;
constexpr uint32_t kBadRaw = 0x00000204u;  // bswap(0x04020000)
constexpr int kMaxWatchHits = 50000;  // a pagina e quente (list walks); o escritor real vem depois
constexpr int kMaxWatchLogs = 0;  // sem log por hit (janela aberta); so BAD/armed/give-up

std::atomic<uint8_t*> g_watch_page{nullptr};
std::atomic<int> g_watch_hits{0};
std::atomic<int> g_watch_logs{0};
std::atomic<bool> g_watch_done{false};
// Single-step credits: the watched page is hot on several guest threads, so several
// faults (each setting TF on its own thread) can be in flight at once. A bool loses
// track and a stray step then escapes to the OS (exit 0x80000004); a counter balances.
std::atomic<int> g_watch_stepping{0};
void* g_watch_handle = nullptr;
// Previous-hit stash for writer attribution (see above).
uintptr_t g_prev_fault = 0;
uintptr_t g_prev_pc = 0;
uint32_t g_prev_lr = 0;
int g_prev_hit = 0;

constexpr DWORD kSingleStep = 0x80000004u;  // EXCEPTION_SINGLE_STEP

LONG CALLBACK WatchHandler(EXCEPTION_POINTERS* info) {
  const DWORD code = info->ExceptionRecord->ExceptionCode;
  if (code == kSingleStep) {
    // Our own single step after a watched hit: re-arm and go on.
    if (g_watch_stepping.fetch_sub(1) <= 0) {
      g_watch_stepping.fetch_add(1);
      REXLOG_CRITICAL("[watch] stray single-step with no credit; continuing search");
      rex::FlushLogging();
      return EXCEPTION_CONTINUE_SEARCH;
    }
    info->ContextRecord->EFlags &= ~DWORD(0x100);
    uint8_t* page = g_watch_page.load();
    if (page && !g_watch_done.load()) {
      DWORD old = 0;
      VirtualProtect(page, 4096, PAGE_NOACCESS, &old);
    }
    return EXCEPTION_CONTINUE_EXECUTION;
  }
  if (code != EXCEPTION_ACCESS_VIOLATION) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  uint8_t* page = g_watch_page.load();
  if (!page || g_watch_done.load()) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  const uintptr_t fault = info->ExceptionRecord->ExceptionInformation[1];
  const uintptr_t start = reinterpret_cast<uintptr_t>(page);
  if (fault < start || fault >= start + 4096) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  const int hit = g_watch_hits.fetch_add(1) + 1;
  const uintptr_t node = start + (kWatchGuest & 0xFFFu);
  DWORD old = 0;
  VirtualProtect(page, 4096, PAGE_READWRITE, &old);
  // Minimal open window: check both dwords FIRST (a few instructions), log only after
  // re-arming or disarming. Logging here (milliseconds) used to leave the page open for
  // other threads and the writer slipped through.
  uint32_t raw0 = 0, raw1 = 0;
  __builtin_memcpy(&raw0, reinterpret_cast<void*>(node), sizeof(raw0));
  __builtin_memcpy(&raw1, reinterpret_cast<void*>(node + 4), sizeof(raw1));
  const bool found = (raw0 == kBadRaw || raw1 == kBadRaw);
  const uintptr_t pc = reinterpret_cast<uintptr_t>(info->ExceptionRecord->ExceptionAddress);
  uint32_t guest_lr = 0;
  auto* ts = rex::runtime::ThreadState::Get();
  if (ts && ts->context()) {
    guest_lr = static_cast<uint32_t>(ts->context()->lr);
  }
  // Always log touches to the node itself (small volume, decisive); other page
  // traffic stays silent.
  const bool on_node = (fault >= node && fault < node + 32);
  // Stash this hit: if a LATER hit finds BAD, the writer is almost surely the faulting
  // instruction of the immediately preceding hit (same thread burst), not the observer.
  // Snapshot first: the log below must show the PREVIOUS hit, not this one.
  const uintptr_t snapshot_fault = g_prev_fault;
  const uintptr_t snapshot_pc = g_prev_pc;
  const uint32_t snapshot_lr = g_prev_lr;
  const int snapshot_hit = g_prev_hit;
  g_prev_fault = fault;
  g_prev_pc = pc;
  g_prev_lr = guest_lr;
  g_prev_hit = hit;
  const bool give_up = !found && hit >= kMaxWatchHits;
  if (found || give_up) {
    g_watch_done.store(true);
    if (g_watch_handle) {
      RemoveVectoredExceptionHandler(g_watch_handle);
      g_watch_handle = nullptr;
    }
    // Page already READWRITE from above; disarmed for good.
    if (found) {
      REXLOG_CRITICAL("[watch] writer found after {} hits; watch removed", hit);
    } else {
      REXLOG_CRITICAL("[watch] gave up after {} hits without seeing {:08X}; watch removed", hit,
                      kBadRaw);
    }
  } else {
    // Correct dance: page stays open, TF carries the re-arm to the single step that
    // fires after re-execution. (Re-protecting here would fault the re-execution itself
    // into an infinite loop.) Per-hit logging is OFF (kMaxWatchLogs=0): formatting is
    // milliseconds with the page open and the writer used to slip through it.
    g_watch_stepping.fetch_add(1);
    info->ContextRecord->EFlags |= DWORD(0x100);
  }
  if (found || on_node) {
    g_watch_logs.fetch_add(1);
    HMODULE module = nullptr;
    HMODULE prev_module = nullptr;
    char path[MAX_PATH] = "?";
    char prev_path[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCSTR>(pc), &module) &&
        module) {
      GetModuleFileNameA(module, path, MAX_PATH);
    }
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCSTR>(g_prev_pc), &prev_module) &&
        prev_module) {
      GetModuleFileNameA(prev_module, prev_path, MAX_PATH);
    }
    const char* name = std::strrchr(path, '\\');
    const char* prev_name = std::strrchr(prev_path, '\\');
    const bool has_prev = snapshot_hit > 0 && prev_module != nullptr;
    REXLOG_WARN("[watch] hit #{} fault={:08X} writer={}+0x{:X} guest_lr={:08X} "
                "[node+0]={:08X} [node+4]={:08X} prev=#{} {}+0x{:X} lr={:08X}{}",
                hit, static_cast<uint32_t>(fault), name ? name + 1 : path,
                pc - reinterpret_cast<uintptr_t>(module), guest_lr, raw0, raw1, snapshot_hit,
                has_prev ? (prev_name ? prev_name + 1 : prev_path) : "none",
                has_prev ? snapshot_pc - reinterpret_cast<uintptr_t>(prev_module) : 0,
                has_prev ? snapshot_lr : 0,
                found ? "  <<< BAD VALUE WRITTEN" : "");
    rex::FlushLogging();
  }
  return EXCEPTION_CONTINUE_EXECUTION;  // re-execute the access (page re-armed or disarmed above)
}

}  // namespace

// Arms the node watch from a hook (base = arena host base). Called when the allocator
// returns the deterministic node address; safe to call every boot (one-shot per process).
void Fc3ArmNodeWatch(uint8_t* host_base, uint32_t guest_addr) {
  if (guest_addr != kWatchGuest || g_watch_page.load() || g_watch_done.load()) {
    return;
  }
  // Same translation the generated code uses (REX_PHYS_HOST_OFFSET in the PCH): guest
  // addresses at or above 0xE0000000 go through a +0x1000 host offset, so the watched
  // host page must include it or the watch sits one page off and sees only noise.
  const uintptr_t host_off = (guest_addr >= 0xE0000000u) ? 0x1000u : 0u;
  uint8_t* page = host_base + (guest_addr & ~0xFFFu) + host_off;
  DWORD old = 0;
  if (!VirtualProtect(page, 4096, PAGE_NOACCESS, &old)) {
    REXLOG_CRITICAL("[watch] VirtualProtect failed for {:08X}", guest_addr);
    return;
  }
  g_watch_page.store(page);
  // Late registration puts this ahead of the SDK's own AV handler.
  g_watch_handle = AddVectoredExceptionHandler(1, WatchHandler);
  REXLOG_WARN("[watch] armed for guest {:08X} (host page {:p})", guest_addr,
              static_cast<void*>(page));
  rex::FlushLogging();
}

namespace {

LONG CALLBACK LogFatalException(EXCEPTION_POINTERS* info) {
  const DWORD code = info->ExceptionRecord->ExceptionCode;
  switch (code) {
    case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_PRIV_INSTRUCTION:
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    case EXCEPTION_STACK_OVERFLOW:
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
    case STATUS_STACK_BUFFER_OVERRUN:
      break;
    default:
      return EXCEPTION_CONTINUE_SEARCH;
  }
  const auto pc = reinterpret_cast<uintptr_t>(info->ExceptionRecord->ExceptionAddress);
  HMODULE module = nullptr;
  char path[MAX_PATH] = "?";
  if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCSTR>(pc), &module) && module) {
    GetModuleFileNameA(module, path, MAX_PATH);
  }
  const char* name = std::strrchr(path, '\\');
  REXLOG_CRITICAL("[crash] host exception {:08X} at {:016X} ({}+0x{:X}) on thread {}", uint32_t(code), pc,
                  name ? name + 1 : path, pc - reinterpret_cast<uintptr_t>(module), GetCurrentThreadId());
  rex::FlushLogging();
  return EXCEPTION_CONTINUE_SEARCH;
}

// Installed before main, first in the chain; it only logs and never handles.
const PVOID g_handler = AddVectoredExceptionHandler(1, LogFatalException);

}  // namespace

#endif
