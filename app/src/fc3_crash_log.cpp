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
constexpr int kMaxWatchHits = 2000;
constexpr int kMaxWatchLogs = 120;

std::atomic<uint8_t*> g_watch_page{nullptr};
std::atomic<int> g_watch_hits{0};
std::atomic<int> g_watch_logs{0};
std::atomic<bool> g_watch_done{false};
void* g_watch_handle = nullptr;

LONG CALLBACK WatchHandler(EXCEPTION_POINTERS* info) {
  if (info->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) {
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
  uint32_t raw = 0;
  __builtin_memcpy(&raw, reinterpret_cast<void*>(node), sizeof(raw));
  const uintptr_t pc = reinterpret_cast<uintptr_t>(info->ExceptionRecord->ExceptionAddress);
  uint32_t guest_lr = 0;
  auto* ts = rex::runtime::ThreadState::Get();
  if (ts && ts->context()) {
    guest_lr = static_cast<uint32_t>(ts->context()->lr);
  }
  const bool found = (raw == kBadRaw);
  if (found || g_watch_logs.load() < kMaxWatchLogs) {
    g_watch_logs.fetch_add(1);
    HMODULE module = nullptr;
    char path[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCSTR>(pc), &module) &&
        module) {
      GetModuleFileNameA(module, path, MAX_PATH);
    }
    const char* name = std::strrchr(path, '\\');
    REXLOG_WARN("[watch] hit #{} fault={:08X} writer={}+0x{:X} guest_lr={:08X} [node]={:08X}{}",
                hit, static_cast<uint32_t>(fault), name ? name + 1 : path,
                pc - reinterpret_cast<uintptr_t>(module), guest_lr, raw,
                found ? "  <<< BAD VALUE WRITTEN" : "");
    rex::FlushLogging();
  }
  if (found || hit >= kMaxWatchHits) {
    g_watch_done.store(true);
    if (g_watch_handle) {
      RemoveVectoredExceptionHandler(g_watch_handle);
      g_watch_handle = nullptr;
    }
    if (found) {
      REXLOG_CRITICAL("[watch] writer found after {} hits; watch removed", hit);
    } else {
      REXLOG_CRITICAL("[watch] gave up after {} hits without seeing {:08X}; watch removed", hit,
                      kBadRaw);
    }
    rex::FlushLogging();
    return EXCEPTION_CONTINUE_EXECUTION;  // re-execute the write, now unprotected
  }
  DWORD old2 = 0;
  VirtualProtect(page, 4096, PAGE_NOACCESS, &old2);
  return EXCEPTION_CONTINUE_EXECUTION;
}

}  // namespace

// Arms the node watch from a hook (base = arena host base). Called when the allocator
// returns the deterministic node address; safe to call every boot (one-shot per process).
void Fc3ArmNodeWatch(uint8_t* host_base, uint32_t guest_addr) {
  if (guest_addr != kWatchGuest || g_watch_page.load() || g_watch_done.load()) {
    return;
  }
  uint8_t* page = host_base + (guest_addr & ~0xFFFu);
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
