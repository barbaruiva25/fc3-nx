// PC build: the pieces of the native renderer (src/me) that the app links against even when
// fc3_BUILD_NATIVE_RENDERER is OFF.
//
// The app's CPU side (app/src/cpu/fc3_gpu_wait.cpp) and the profiler ask the renderer's ring thread how far it has
// got, so the frame the game drew is the frame that was presented. With the native renderer off there is no ring
// thread: the app draws with ReXGlue's emulated Xenos GPU, which the SDK runs on its own thread and reports through
// its own interface. These stubs keep the link whole and say "no progress, no wait", which is the honest answer for
// a renderer that is not there: the game then spins as it did before the wait optimisation, which is correct, only
// slower.

#include <cstdint>

// The Switch profiler counters the renderer reports to (sdk/src/ui/switch_perf.cpp on the Switch) have nothing to
// feed on PC.
extern "C" void RexSwitchPerfCount(unsigned) {}
extern "C" void RexSwitchPerfHitch(uint64_t, uint64_t) {}

// me_ring_wait.cpp, when the renderer is not built. Declared in src/me/me_ring_wait.cpp's own header; these are the
// definitions the app's references bind to.
namespace me::native {

void NotifyRingProgress() {}

uint32_t RingProgress() { return 0; }

uint64_t PresentedSwaps() { return 0; }

bool WaitRingProgress(uint32_t, uint32_t) { return false; }

void SetPresentHook(void (*)(uint64_t)) {}

}  // namespace me::native

// me_native_system.cpp, when the renderer is not built. fc3App::OnPreSetup asks whether the native renderer is on and,
// only if it is, for the graphics system to create. Both answers here are "no", so the SDK's own Xenos emulation is
// used, which is exactly what fc3_renderer_native = false means at run time.
#include <memory>

#include <rex/graphics/graphics_system.h>

namespace me::native {

bool Enabled() { return false; }

std::unique_ptr<rex::system::IGraphicsSystem> CreateGraphicsSystem() { return nullptr; }

}  // namespace me::native