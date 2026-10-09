// fc3 glue for the native renderer modules: "feature off" answers for the hooks they call that
// have no fc3 implementation (deferred-recording reports) and the shader library handle.
#include <string>

#include <rex/logging.h>

#include "fc3_native_hooks.h"
#include "fc3_native_shaders.h"

namespace fc3::native {
void DeferredReport(std::string line) { REXLOG_INFO("{}", line); }

// Set by the native graphics system once the shader library is loaded.
const ShadersNative* g_active_library = nullptr;
const ShadersNative* ActiveLibrary() { return g_active_library; }
}  // namespace fc3::native
