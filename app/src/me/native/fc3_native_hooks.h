// fc3 - native renderer: access to the shader library the native graphics system has loaded.

#pragma once

namespace fc3::native {

class ShadersNative;

// The library the native graphics system loaded (nullptr until then), from any thread. Used for pipeline
// prewarming (fc3_native_draws.cpp).
const ShadersNative* ActiveLibrary();

}  // namespace fc3::native
