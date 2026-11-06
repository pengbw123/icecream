// Tiny compile-time JUCE surface used only by Dexed's debug logger header.
// The offline reference renderer never creates or uses a JUCE application.
#pragma once
#include <algorithm>
#include <ostream>
#include <string>
#include <vector>

namespace juce {
class String {
public:
    String() = default;
    String(const char *text) : value(text ? text : "") {}
    static String fromUTF8(const char *text) { return String(text); }
    friend std::ostream &operator<<(std::ostream &out, const String &text) {
        return out << text.value;
    }
private:
    std::string value;
};
class StringRef {
public:
    explicit StringRef(const char *) {}
};
class StringArray {
public:
    int size() const { return static_cast<int>(values.size()); }
    void add(const String &value) { values.push_back(value); }
    void clear() { values.clear(); }
    void remove(int index) {
        if (index >= 0 && index < size()) values.erase(values.begin() + index);
    }
    const String &operator[](int index) const { return values[index]; }
    String joinIntoString(StringRef) const { return String(); }
private:
    std::vector<String> values;
};
class CriticalSection {};
class ScopedLock {
public:
    explicit ScopedLock(const CriticalSection &) {}
};
template <typename T> T jmax(T left, T right) { return std::max(left, right); }
class Logger {
public:
    virtual ~Logger() = default;
    static void setCurrentLogger(Logger *logger) { current = logger; }
    static Logger *getCurrentLogger() { return current; }
protected:
    virtual void logMessage(const String &) = 0;
private:
    inline static Logger *current = nullptr;
};
}
#define JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Type)
