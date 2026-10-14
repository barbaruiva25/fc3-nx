# Porting prompt (variante thesims3-nx) — referencia enviada pelo usuario em 2026-10-13

Mantido como referencia secundaria. O fc3-nx segue o guia do sa2-nx
(`docs/porting-a-360-game-prompt.md`); a estrutura em 5 etapas e a mesma,
mudam apenas os nomes (`thesims3_*` vs `fc3_*`) e os detalhes do jogo.

---

Port the Xbox 360 game farcry 3 to Windows PC and then Nintendo Switch by static recompilation with ReXGlue (Xbox 360 PPC to C++), following the architectural pattern of nfsmw-nx, masseffect-nx and thesims3-nx ([thesims3-nx path]). My own game files are at [path] (ISO, extracted GOD container, or XBLA STFS packages). Work in a new folder [path], reuse the thesims3-nx SDK fork (sdk/), tools and renderer, and keep game files and generated code out of the repository. Order of work, one stage at a time, verify each before moving on:
1. Extract and inspect
- STFS (XBLA, DLC): tools/stfs_extract.py (only reads the package). ISO/GOD: tools/extract_iso.py.
- Look for extra code modules: guest DLLs (*.xex inside the data, loaded with XexLoadImage) go in the manifest as [[modules]]. Overlay files or script containers (.package / SimS3 asset archives) should be mapped for asset streaming and package loading hooks. Check prologue styles if legacy compiled modules exist.
2. Build the code generator and translate (Windows: portable LLVM clang 20, VS Build Tools libs, tools/win/env.ps1 and run.ps1; -march=x86-64-v2; fix Git symlink stubs in sdk/thirdparty, fetch_thirdparty.py does it)
- rexglue codegen <manifest>; fix each "target not in any function" with an [functions] entry plus evidence.
- Before booting, sweep the missed-code classes, each with its tool, and re-run after every codegen:
  - functions reached only by pointer (CRT initializer table, vtables, callbacks built with lis/addi): tools/pointer_fixpoint.py, tools/pointer_audit.py
  - truncated jump tables (crash = illegal instruction, "Switch case out of range"): tools/switch_check.py
  - setjmp/longjmp (crash = r1/r31 corrupted after a call returns): find them by shape (std/stfd/stvlx128 into r3 vs the mirrored loads) and set setjmp_address / longjmp_address.
3. Boot on PC with the emulated GPU (thesims3_renderer_native = false)
- Test harness: tools/win/boot_test.ps1 (always muted + minimized; never pipe it into Select-Object -First), video with -VideoAt N -VideoFrames M, MP4 + contact sheet with tools/make_video.sh, frame matching against a reference recording with tools/compare_video.py.
- Crash triage: unregistered call -> pointer/gap class; guest access violation -> symbolize thesims3.exe+0xRVA with llvm-symbolizer (app/src/thesims3_crash_log.cpp logs illegal instructions too); temporary caller-logging hooks in a debug-hooks file.
- XBLA/DLC: license_mask = 1 for full content; package loading redirection hooked for virtualized filesystem paths used by The Sims 3 engine (app/src/thesims3_vfs.cpp).
- Send a subagent to audit crash classes in a COPY of the tree while you continue.
4. Native renderer on PC (the PM4-ring Vulkan renderer from masseffect-nx via banjo-nx, app/src/me)
- Find the game's D3D functions: tools/d3d_match.py against a game with named XDK functions, confirm by call alignment (tools/listing_diff.py). Hooks needed: draw-time shader load (+ the device's bound VS/PS offsets, which move between XDK versions; pass them to SetDeviceShaderOffsets), DrawVertices/DrawIndexedVertices/DrawVerticesUP (pass the device, r3, to NoteDrawCall), CreateVertexShader/CreatePixelShader (shader dump), the flip (frames).
- Shader library loop until the log says 0 unidentified loads: dump containers (*_dump_shaders), run native with THESIMS3_SHADER_DISCOVERY, THESIMS3_VERTEX_VARIANTS, THESIMS3_SHADER_MISSING; repair D3D-patched variants (repair_vertex_variant_declarations, binary-mode output); wrap ONLY shaders no real container covers (tools/wrap_discovered.py); build with tools/build_shader_library.sh (XenosRecomp + DXC + packer).
- Compare native against emulated frame by frame (compare_video.py on two raw captures of the same window), and trace single frames (banjo_trace_frame_s, THESIMS3_DUMP_TEXTURE) for every difference. Done = no visible difference across boot, main menu, Create-a-Sim (CAS), live mode, and loading screens.
- Known XenosRecomp fixes: fetches whose swizzle is all constants; interpolators linked by hardware register for every shader.
5. Then GPU optimizations, then Switch (devkitA64 + libnx, NVK from mesa-switch, the SDK's Horizon layer; read nfsmw-nx docs/platform-notes.md, toolchain.md, measuring.md first). Every optimization must be pixel-identical (verify with compare_video.py) and measured on the console.
Rules: every analysis entry carries its evidence; test runs never take over the desktop (muted, minimized); no game data in the repo; report results faithfully, including what was not verified.
