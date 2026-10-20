// Calls the user's unmodified Dexed/msfa sine implementation. The build tool
// compiles this adapter with sin.cc; no Dexed source is copied into the repo.
#include <cstdint>
#include <cstdio>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
#include "sin.h"

int main() {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    Sin::init();
    uint32_t phase_q32;
    while (std::fread(&phase_q32, sizeof(phase_q32), 1, stdin) == 1) {
        // Both engines represent one cycle by an unsigned phase word. Dexed
        // uses 24 fractional phase bits, while the RTL stores 32.
        const int32_t value = Sin::lookup(
            static_cast<int32_t>(phase_q32 >> 8));
        if (std::fwrite(&value, sizeof(value), 1, stdout) != 1)
            return 2;
    }
    return std::ferror(stdin) ? 2 : 0;
}
