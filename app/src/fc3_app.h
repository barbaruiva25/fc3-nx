// Far Cry 3: the ReXGlue application object (paths, GPU plugin choice, analysis aids).

#pragma once

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <system_error>

#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/logging.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>

#include "cpu/fc3_enhancements.h"
#include "me/me_native_system.h"
#include "me/fc3_render_mode.h"
#include "profiler/fc3_cpu_profile_pc.h"
#include "fc3_capture.h"
#include "fc3_dlc.h"
#include "fc3_language.h"
#include "fc3_pgo.h"

#if defined(fc3_BUILTIN_CONFIG)
#include "fc3_builtin_config.h"  // generated from app/fc3_switch_defaults.toml (CMake)
#endif

class fc3App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<fc3App>(new fc3App(ctx, "fc3", PPCImageConfig));
  }

  // The Switch build's fixed settings (app/fc3_switch_defaults.toml, compiled in): applied before fc3.toml, which
  // holds only the player's options (and may still override any of these).
  std::string_view BuiltInConfig() const override {
#if defined(fc3_BUILTIN_CONFIG)
    return kfc3BuiltInConfig;
#else
    return {};
#endif
  }
  // Without an fc3.toml next to the NRO, the player's default one is written there (app/fc3_switch.toml).
  std::string_view DefaultConfigFile() const override {
#if defined(fc3_BUILTIN_CONFIG)
    return kfc3PlayerConfig;
#else
    return {};
#endif
  }

  void OnPostInitLogging() override {
    // The runtime defaults to no GPU plugin: select ReXGlue's Xenos implementation, keeping an explicit
    // command-line or config-file choice.
    if (!rex::cvar::HasNonDefaultValue("gpu_plugin")) {
      rex::cvar::SetFlagByName("gpu_plugin", "xenos");
    }
    // Which enhancements run (own key + group master), in one line; before any guest thread exists.
    fc3::enh::Resolve();
    // The game's language (fc3.toml "language"; auto = the system language): before the game asks for it.
    fc3::language::Apply();
  }

  // Without --game_data_root, use a game_root/ folder next to the executable (on the Switch:
  // sdmc:/switch/fc3-nx/game_root), and on a PC build tree the repository's assets/game_root.
  // An explicit path always wins.
  void OnConfigurePaths(rex::PathConfig& paths) override {
    if (!paths.game_data_root.empty()) {
      return;
    }
    std::error_code ec;
    const auto folder = rex::filesystem::GetExecutableFolder();
    if (folder.empty()) {
      return;
    }
    for (auto candidate = folder; !candidate.empty(); candidate = candidate.parent_path()) {
      for (const auto& sub : {std::filesystem::path("game_root"),
                              std::filesystem::path("assets") / "game_root"}) {
        // The folder itself, or only its asset cache (game_root.nxpack + .nxidx, see sdk pack_device.h).
        auto pack = candidate / sub;
        pack += ".nxpack";
        if (std::filesystem::is_regular_file(candidate / sub / "default.xex", ec) ||
            std::filesystem::is_regular_file(pack, ec)) {
          paths.game_data_root = candidate / sub;
          return;
        }
      }
      if (candidate == candidate.parent_path()) {
        break;
      }
    }
  }

  // Stage 2: with fc3_renderer_native = true the graphics system is the app's own native Vulkan renderer
  // (src/me), and the emulated Xenos GPU plugin is not loaded (ReXApp only loads it when config.graphics is empty).
  void OnPreSetup(rex::RuntimeConfig& config) override {
    fc3::enh::ApplyGpuBoost();
    if (me::native::Enabled()) {
      config.graphics = me::native::CreateGraphicsSystem();
      REXLOG_INFO("graphics: native Vulkan renderer (PM4 ring)");
    }
  }

  // Video recording of the game image for testing (fc3_video_s = N seconds after start; 0 = off). Taken from the
  // presenter's guest output, so it works minimized and nothing can cover it.
  void OnPostSetup() override {
    // PC only: the sampling CPU profiler (fc3_cpu_profile_from_s) and the stack dump (fc3_stack_dump_s).
    nfsmw::perfil_pc::Arrancar();
    // Every 10 s: how often each active enhancement was used (a log shows they really ran).
    fc3::enh::StartReport();
    // DLC packages from dlc/ next to the executable go into the content store before the game starts looking.
    fc3::dlc::InstallPackages(runtime());
    // PC: the key that simulates docking / undocking (render resolution, bind_fc3_docked = F9).
    fc3::render::RegisterKeys();
    fc3::capture::Start([this]() -> rex::ui::Presenter* {
      const auto* rt = runtime();
      const auto* graphics = rt ? rt->graphics_system() : nullptr;
      return graphics ? graphics->presenter() : nullptr;
    });
    // The PGO-instrumented build (fc3_PGO=generate) saves its counts to pgo/ every 2 minutes (nothing otherwise).
    fc3::pgo::Start();
  }

  // The PGO-instrumented build saves its counts when the game loses focus (HOME menu): it may be closed from there.
  void OnWindowFocusChanged(bool focused) override {
    if (!focused) fc3::pgo::DumpNow();
  }

  void OnShutdown() override {
    nfsmw::perfil_pc::Parar();
    fc3::capture::Stop();
    fc3::pgo::Stop();
  }

  // Analysis aid: with fc3_DUMP_IMAGE=<file>, write the loaded guest image (image_base..image_base+image_size) so
  // code pointers stored in data can be scanned for (tools/pointer_scan.py). Does nothing unless the variable is set.
  void OnPostLoadXexImage() override {
    if (!runtime() || !runtime()->memory()) {
      return;
    }
    const char* path = std::getenv("fc3_DUMP_IMAGE");
    if (!path) {
      return;
    }
    const uint8_t* image =
        runtime()->memory()->TranslateVirtual<const uint8_t*>(PPCImageConfig.image_base);
    if (std::FILE* f = std::fopen(path, "wb")) {
      std::fwrite(image, 1, PPCImageConfig.image_size, f);
      std::fclose(f);
      REXLOG_INFO("guest image written to {}", path);
    }
  }
};
