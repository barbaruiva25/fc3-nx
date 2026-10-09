# Building sa2-nx

How to build the Windows PC build (used for development and testing), the Nintendo Switch NRO, the shader package and
the SD card folder, from your own copy of the game.

## What you need

- **Your own XBLA copy of Sonic Adventure 2:** the package
  `Content/0000000000000000/58411202/000D0000/525E7BB1E72A2DB99AB79281BA24938048198FAD58` from an Xbox 360. The
  Battle DLC (`58411202/00000002/SonicAdventure2Battle`) is optional.
- **Windows 10/11** with:
  - VS 2022 Build Tools (the MSVC libraries and the Windows SDK; CMake and Ninja come with it);
  - LLVM clang 20 (a portable copy is fine; by default `..\_tools\llvm`);
  - Python 3 and Git.

  `tools/win/env.ps1` finds them; override the paths with `SA2_LLVM`, `SA2_VSDIR` and `SA2_CMAKE_DIR`.
- **For the Switch:**
  - [devkitPro](https://devkitpro.org) with devkitA64 and libnx;
  - the NVK Vulkan driver built from [mesa-switch](https://github.com/danfromtico/mesa-switch), as a static
    `libvulkan.a`. SA2 links nfsmw-nx's build; set `NVK_SDK` to another one;
  - glslangValidator (`tools/win/build_glslang.ps1` builds it into `out/glslang`).

Run every build command from PowerShell, through `tools\win\run.ps1` or the scripts below. Running `cmake` from a
Bash shell picks up MSYS2's tools: the configure fails and wipes the build folder's cache.

## 1. Extract the game

```powershell
# Your package (it is only read, never written; ~2.4 GB)
python tools\stfs_extract.py "<...>\58411202\000D0000\525E7BB1E72A2DB99AB79281BA24938048198FAD58" assets\game_root
# Optional: the Battle DLC, installed by the game from dlc\ at start
mkdir out\pc\dlc; copy "<...>\58411202\00000002\SonicAdventure2Battle" out\pc\dlc\
```

## 2. Translate the game's code to C++

```powershell
python tools\fetch_thirdparty.py                       # third-party sources of the SDK
powershell -File tools\win\run.ps1 out\host_configure.log "cmake -S sdk -B out/host -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
powershell -File tools\win\run.ps1 out\host_build.log "cmake --build out/host --target rexglue"
powershell -File tools\codegen.ps1                     # default.xex and the stage DLL -> app/generated (git-ignored)
```

`tools/codegen.ps1` also runs the post-codegen steps of the optimised flavour (`tools/post_codegen.py`: the
no-volatile precompiled header, direct calls, the localized native copies).

## 3. The PC build

```powershell
powershell -File tools\win\run.ps1 out\pc_configure.log "cmake --preset win-pc -S app"
powershell -File tools\win\run.ps1 out\pc_build.log "cmake --build out/pc"
powershell -File tools\win\boot_test.ps1               # 45 s, muted and minimized, then the end of the log
```

`out\pc\sa2.toml` holds the PC's settings. It starts **muted and minimized** (`audio_mute`, `window_start_minimized`)
so test runs stay out of the way; set both to `false` to play. `license_mask = 1` runs the full game rather than the
XBLA trial, and `sa2_renderer_native = true` (or the environment variable `REX_SA2_RENDERER_NATIVE=true`) uses the
native Vulkan renderer instead of the emulated GPU.

To record a video while it runs minimized, give `-VideoAt <seconds after start>` and optionally `-VideoFrames` (60
per second). The MP4 and a contact sheet land in `out\pc\captures\` (needs ffmpeg at `C:\ffmpeg\ffmpeg.exe`, or set
`FFMPEG`):

```powershell
powershell -File tools\win\boot_test.ps1 -VideoAt 8 -VideoFrames 600
```

## 4. The shader package

The native renderer draws with the game's shaders translated ahead of time (XenosRecomp to HLSL, DXC to SPIR-V) into
`sa2_shaders.mesp` + `sa2_shaders.mesp.idx`.

1. Run the PC build once with `sa2_dump_shaders = true`: every container the game creates is written to `shaders/`
   next to `sa2.exe`.
2. Build the package from those dumps:

   ```bash
   tools/build_shader_library.sh out/pc/shaders
   ```

Direct3D's own shaders and the variants Direct3D rewrites at run time are found with the discovery dumps
(`SA2_SHADER_DISCOVERY`, `SA2_VERTEX_VARIANTS`, `SA2_SHADER_MISSING`) and `tools/wrap_discovered.py`.
[porting-guide.md](porting-guide.md), chapter 6, explains the whole loop.

## 5. The Switch NRO

```powershell
powershell -File tools\win\build_switch.ps1            # out\nx\sa2.nro (LTO: allow 15-30 minutes)
python tools\check_switch_build.py                     # start-up code at 0, flavour, driver, no vector FMA, ...
powershell -File tools\win\package_switch.ps1          # the SD card folder: out\nx\sdcard\switch\sa2-nx
powershell -File tools\win\package_switch.ps1 -IncludeGame   # the same with the game as game_root.nxpack
```

`build_switch.ps1` configures `out\nx` the first time (`-Reconfigure` does it again). The NRO's name, author, version
and icon (`app/icon.jpg`) are in `app/CMakeLists.txt`. The settings compiled into the NRO are
`app/sa2_switch_defaults.toml`, and the player's `sa2.toml` is `app/sa2_switch.toml`.

### Profile-guided optimisation

`pgo/` holds the profile the released NRO was built with (one console session of version 1.0.0). To build with it:

```powershell
powershell -File tools\win\build_switch.ps1 -Pgo use
```

`-Pgo none` goes back to a build without PGO. The profile matches the code of this repository: a function you change
loses its part of it, and the rest still applies. [pgo/README.md](../pgo/README.md) explains its file names and what
applies when you build from another folder.

To record a new profile:

1. `build_switch.ps1 -Pgo generate` builds an instrumented NRO. Play it on the console: it writes
   `pgo/sa2_pgo_<N>.stream` next to the NRO (one file per session, saved every 2 minutes and on the HOME button).
2. Move the `.gcda` files of `pgo\` aside, copy the console's `pgo` folder to the PC, and run
   `powershell -File tools\win\pgo_merge.ps1 <folder>`. It merges every session into `pgo\` and fills in each file's
   summary. Merge on the PC that built the instrumented NRO: the streams name its profile folder.
3. `build_switch.ps1 -Pgo use` builds the optimised NRO.

Do not change the game or app code between steps 1 and 3: a changed function loses its profile.

## Tests on the PC

| Script | What it does |
|---|---|
| `tools\win\boot_test.ps1` | One muted, minimized run; `-VideoAt` / `-VideoFrames` record it |
| `tools\make_enhancement_configs.py` | The A/B configurations (`out\nx\configs`) |
| `tools\compare_video.py`, `tools\compare_raw.py` | Line up two recordings frame by frame |
| `shaders\tests\test_vertex_fetch_reorder.cpp` | The run-time proof for reordered vertex fetches (`--orders` for every order) |
| `tools\check_switch_build.py` | The checks every Switch build must pass |

Lockstep captures (`REX_VBLANK_PER_SWAP=true`, `REX_SA2_VIDEO_FRAME=6000`) pin every frame to a presented swap, and
`<name>.hash` keeps the XXH3 of each frame at full resolution. Two runs are equal when their hashes are, frame for
frame (align the labels by content first: each run numbers its swaps from its own start).
