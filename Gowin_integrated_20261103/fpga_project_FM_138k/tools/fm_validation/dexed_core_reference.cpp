// Standalone adapter around the user's Dexed/msfa sources. No msfa code is
// copied here: build_fm_validation.py compiles the original source files.
// This isolates the FM algorithm, sine, gain and feedback from envelopes.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <sstream>
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
#include "fm_core.h"

static std::array<double, 6> parse_six(const char *value) {
    std::array<double, 6> result{};
    std::stringstream input(value);
    std::string part;
    for (int index = 0; index < 6; ++index) {
        if (!std::getline(input, part, ','))
            throw std::runtime_error("expected six comma-separated values");
        result[index] = std::stod(part);
        if (!std::isfinite(result[index]) || result[index] < 0)
            throw std::runtime_error("values must be nonnegative and finite");
    }
    if (std::getline(input, part, ','))
        throw std::runtime_error("expected exactly six values");
    return result;
}

int main(int argc, char **argv) {
    try {
        if (argc != 7)
            throw std::runtime_error(
                "usage: dexed_core_reference samples sample_rate algorithm "
                "feedback freq_hz_op6_to_op1 gain_op6_to_op1");
        const int sample_count = std::stoi(argv[1]);
        const double sample_rate = std::stod(argv[2]);
        const int algorithm = std::stoi(argv[3]);
        const int feedback = std::stoi(argv[4]);
        if (sample_count < 1 || sample_count > 5000000 ||
            sample_rate < 8000 || sample_rate > 192000 ||
            algorithm < 1 || algorithm > 32 || feedback < 0 || feedback > 7)
            throw std::runtime_error("argument out of supported range");
        const auto frequencies = parse_six(argv[5]);
        const auto gains = parse_six(argv[6]);

        Sin::init();
        Exp2::init();
        FmCore core;
        FmOpParams operators[6]{};
        for (int index = 0; index < 6; ++index) {
            const double phase_increment = frequencies[index] / sample_rate *
                                           static_cast<double>(1 << 24);
            if (phase_increment >= static_cast<double>(1 << 24))
                throw std::runtime_error("operator frequency must be below sample rate");
            operators[index].phase = 0;
            operators[index].freq = static_cast<int32_t>(std::llround(phase_increment));
            operators[index].level_in = gains[index] == 0.0 ? 0 :
                static_cast<int32_t>(std::llround(
                    (14.0 + std::log2(gains[index])) * (1 << 24)));
            operators[index].gain_out = gains[index] == 0.0 ? 0 :
                Exp2::lookup(operators[index].level_in - (14 << 24));
        }
        int32_t feedback_history[2] = {0, 0};
        const int feedback_shift = feedback ? 8 - feedback : 16;
        std::vector<int32_t> block(N);
#ifdef _WIN32
        _setmode(_fileno(stdout), _O_BINARY);
#endif
        for (int emitted = 0; emitted < sample_count; emitted += N) {
            std::fill(block.begin(), block.end(), 0);
            core.render(block.data(), operators, algorithm - 1,
                        feedback_history, feedback_shift);
            const int remaining = sample_count - emitted;
            const size_t count = static_cast<size_t>(remaining < N ? remaining : N);
            if (std::fwrite(block.data(), sizeof(int32_t), count, stdout) != count)
                throw std::runtime_error("could not write PCM output");
        }
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 2;
    }
}
