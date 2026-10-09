# The graphics driver (Mesa NVK for the Switch)

The Switch has no Vulkan driver that homebrew can use, so the NRO carries its own: **NVK**, the open source Vulkan
driver for NVIDIA GPUs from the **Mesa** project, with the **NAK** shader compiler, running on Horizon (the Switch's
operating system). It is linked into the NRO as one static library, `libvulkan.a`.

**This port does not change the driver.** It links the NVK build of [nfsmw-nx](https://github.com/StevensND/nfsmw-nx):
[danfromtico/mesa-switch](https://github.com/danfromtico/mesa-switch) (Mesa 26.2.2 with the Horizon backend, with
NaGaa95's updates) plus nfsmw-nx's driver changes by StevensND (ZCULL, NAK scheduling and fixes, a cheaper draw
path...). Those changes, how to apply them and how to build the library are in nfsmw-nx's
[`mesa/` folder](https://github.com/StevensND/nfsmw-nx/tree/main/mesa).

Point the build at the result with `NVK_SDK=<sdk>/opt/devkitpro/portlibs/switch` (`tools/win/build_switch.ps1`) or
`-DREXGLUE_SWITCH_NVK_SDK=` when you configure `app/` yourself ([docs/building.md](../docs/building.md)).

Mesa is under the MIT license (and other permissive licenses per file); see `release/LICENSES.txt` of the installer
page, which ships with every package.
