// Far Cry 3: profile collection of the PGO-instrumented Switch build (fc3_PGO=generate), see fc3_pgo.cpp.
// In every other build these do nothing.

#pragma once

namespace fc3::pgo {

// Picks this session's file (pgo/fc3_pgo_<N>.stream next to the executable) and starts the 2-minute dumps.
void Start();
// Writes every count so far to this session's file (the whole session each time, replacing the previous dump).
void DumpNow();
// The last dump, then the dump thread ends.
void Stop();

}  // namespace fc3::pgo
