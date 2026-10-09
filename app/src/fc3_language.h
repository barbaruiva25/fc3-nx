// Far Cry 3: the game's language (fc3.toml "language"), see fc3_language.cpp.

#pragma once

namespace fc3::language {

// Sets the SDK's user_language from the "language" setting ("auto" = the console's / PC's language). Before any guest
// code runs: the game asks for it at start (XGetLanguage).
void Apply();

}  // namespace fc3::language
