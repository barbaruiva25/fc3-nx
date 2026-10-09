// Far Cry 3: the handheld GPU profile (non-CPU enhancement fc3_gpu_boost).
//
// Asks the console's performance manager for the official handheld configuration 0x92220008 (GPU 460.8 MHz, memory
// 1331.2 MHz; the same as UnleashedRecomp-NX, MarathonRecomp-NX and masseffect-nx), through the SDK's switch_apm.cpp,
// which checks with the real clocks for 1.5 s that the memory clock did not move and reverts if it did. Docked: nothing
// is requested.
// WHY IT IS EXACT: a clock, not a setting: the same frames are drawn, sooner.
// RISK: more power draw in handheld mode.
// KEY: fc3_gpu_boost (with fc3_noncpu_enhancements).
#include <rex/logging.h>
#include <rex/platform.h>

#include "cpu/fc3_enhancements.h"

#if REX_PLATFORM_SWITCH
extern "C" {
void RexSwitchApmRequestGpuMhz(int mhz);
void RexSwitchApmApply(void);
}
#endif

fc3_ENHANCEMENT(g_gpu_boost, fc3_gpu_boost, fc3::enh::kNonCpu, true,
                "Handheld: ask for the official 460.8 MHz GPU profile (memory clock checked unchanged, else reverted)");

namespace fc3::enh {

void ApplyGpuBoost() {
  if (!g_gpu_boost.active) return;
#if REX_PLATFORM_SWITCH
  RexSwitchApmRequestGpuMhz(460);
  RexSwitchApmApply();  // logs what it did on stderr (rex_stderr.log)
  g_gpu_boost.Use();
#endif
}

}  // namespace fc3::enh
