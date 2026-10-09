// Downloadable content: installs the Xbox 360 content packages (STFS) found in a dlc/ folder next to the executable
// into the runtime's content store, before the game starts, so the game finds them the way the console would.

#pragma once

namespace rex {
class Runtime;
}

namespace fc3::dlc {

// Installs every package in <exe folder>/dlc (or the folder in fc3_dlc_dir) that is not installed yet.
void InstallPackages(rex::Runtime* runtime);

}  // namespace fc3::dlc
