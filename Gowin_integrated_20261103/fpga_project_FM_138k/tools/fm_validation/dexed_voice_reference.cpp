// Standalone adapter for the complete Dexed/msfa single-note path.
// It compiles the user's original Dexed source files without copying them.
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include "synth.h"
#include "sin.h"
#include "exp2.h"
#include "freqlut.h"
#include "env.h"
#include "lfo.h"
#include "fm_core.h"
#include "dx7note.h"

void dexed_trace(const char *, const char *, ...) {}

class EqualTemperament final : public TuningState {
public:
    EqualTemperament() {
        constexpr int32_t a4_log2_q24 = 50857777;
        constexpr int32_t semitone_q24 = (1 << 24) / 12;
        for (int note = 0; note < 128; ++note)
            log_frequency[note] = a4_log2_q24 + semitone_q24 * note;
    }
    int32_t midinote_to_logfreq(int note) override {
        return log_frequency[std::clamp(note, 0, 127)];
    }
private:
    int32_t log_frequency[128]{};
};

int main(int argc, char **argv) {
    try {
        if (argc != 7)
            throw std::runtime_error(
                "usage: dexed_voice_reference patch156.bin note velocity sample_rate hold_samples total_samples");
        const int note_number = std::stoi(argv[2]);
        const int velocity = std::stoi(argv[3]);
        const double sample_rate = std::stod(argv[4]);
        const int hold_samples = std::stoi(argv[5]);
        const int total_samples = std::stoi(argv[6]);
        if (note_number < 0 || note_number > 127 || velocity < 1 || velocity > 127 ||
            sample_rate < 8000.0 || sample_rate > 192000.0 || hold_samples < 1 ||
            total_samples < hold_samples || total_samples > 10000000)
            throw std::runtime_error("note, velocity, or sample rate is out of range");

        std::array<uint8_t, 156> patch{};
        std::ifstream patch_file(argv[1], std::ios::binary);
        patch_file.read(reinterpret_cast<char *>(patch.data()), patch.size());
        if (patch_file.gcount() != static_cast<std::streamsize>(patch.size()) ||
            patch_file.peek() != std::char_traits<char>::eof())
            throw std::runtime_error("patch file must contain exactly 156 bytes");

        Sin::init();
        Exp2::init();
        Freqlut::init(sample_rate);
        Env::init_sr(sample_rate);
        Lfo::init(sample_rate);

        FmCore core;
        Controllers controllers{};
        controllers.pitch_cc = 8192;
        controllers.pitch_range_up = 2;
        controllers.pitch_range_dn = 2;
        controllers.pitch_step = 0;
        controllers.amp_mod = 0;
        controllers.pitch_mod = 0;
        controllers.eg_mod = 127;
        controllers.aftertouch_cc = 0;
        controllers.breath_cc = 0;
        controllers.foot_cc = 0;
        controllers.modwheel_cc = 0;
        controllers.portamento_enable_cc = false;
        controllers.portamento_cc = 0;
        controllers.portamento_gliss_cc = false;
        controllers.masterTune = 0;
        controllers.mpeEnabled = false;
        controllers.core = &core;

        auto tuning = std::make_shared<EqualTemperament>();
        Dx7Note voice(tuning, nullptr);
        voice.init(patch.data(), note_number, velocity, 1, &controllers);
        Lfo lfo{};
        lfo.reset(patch.data() + 137);
        lfo.keydown();

        std::array<int32_t, N> block{};
#ifdef _WIN32
        _setmode(_fileno(stdout), _O_BINARY);
#endif
        for (int emitted = 0; emitted < total_samples; emitted += N) {
            if (emitted >= hold_samples && emitted - N < hold_samples)
                voice.keyup();
            block.fill(0);
            const int32_t lfo_value = lfo.getsample();
            const int32_t lfo_delay = lfo.getdelay();
            voice.compute(block.data(), lfo_value, lfo_delay, &controllers);
            const size_t count = static_cast<size_t>(
                std::min(N, total_samples - emitted));
            if (std::fwrite(block.data(), sizeof(int32_t), count, stdout) != count)
                throw std::runtime_error("failed to write rendered samples");
        }
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 2;
    }
}
