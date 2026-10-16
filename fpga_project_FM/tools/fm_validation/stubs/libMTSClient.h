// Minimal no-MTS implementation for offline equal-temperament rendering.
// The real Dexed/MTS-ESP source tree remains untouched.
#pragma once
class MTSClient {};
inline bool MTS_HasMaster(MTSClient *) { return false; }
inline double MTS_NoteToFrequency(MTSClient *, int, int) { return 440.0; }
