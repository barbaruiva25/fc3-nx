// Switch build with the native renderer off (stage 1): the pieces of src/me that the app links
// against even when fc3_BUILD_NATIVE_RENDERER is OFF.
//
// Same role as me_pc_stubs.cpp on PC, but without the parts that already exist on the Switch:
// RexSwitchPerfCount/RexSwitchPerfHitch live in sdk/src/ui/switch_perf.cpp, and the CPU profiler is
// PC-only, so only the me::native interface the app references stays here.
//
// Semantics are the same honest ones as the PC stubs: with the native renderer off there is no ring
// thread, the app draws with ReXGlue's emulated Xenos GPU, and "no progress, no wait" is the correct
// answer:
//   - Enabled() = false -> fc3_app.h::OnPreSetup leaves config.graphics empty and the SDK loads its
//     own Xenos emulation, exactly like fc3_renderer_native = false on PC.
//   - PresentedSwaps/SetPresentHook: fc3_capture.cpp's video capture; no swaps, no hook.

#include <cstdint>
#include <memory>

#include <rex/graphics/graphics_system.h>

namespace me::native {

bool Enabled() { return false; }

std::unique_ptr<rex::system::IGraphicsSystem> CreateGraphicsSystem() { return nullptr; }

uint64_t PresentedSwaps() { return 0; }

void SetPresentHook(void (*)(uint64_t)) {}

}  // namespace me::native