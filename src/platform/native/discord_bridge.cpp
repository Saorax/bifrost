#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr std::uint32_t kHandshake = 0;
constexpr std::uint32_t kFrame = 1;
constexpr std::uint32_t kClose = 2;
constexpr DWORD kTickMs = 100;
constexpr DWORD kRetryMs = 5000;
constexpr DWORD kHandshakeMs = 3000;

HANDLE discord_pipe = INVALID_HANDLE_VALUE;
std::string inbox;
unsigned long nonce_counter = 0;
DWORD activity_pid = 0;
std::wstring pipe_base = L"\\\\?\\pipe\\discord-ipc-";

std::mutex lines_mutex;
std::deque<std::string> lines;
std::atomic<bool> input_closed{false};

void emit(HANDLE stream, const std::string& text) {
    if (stream == INVALID_HANDLE_VALUE || stream == nullptr) return;
    DWORD written = 0;
    WriteFile(stream, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
}

void emit_stdout(const std::string& text) { emit(GetStdHandle(STD_OUTPUT_HANDLE), text); }
void emit_stderr(const std::string& text) { emit(GetStdHandle(STD_ERROR_HANDLE), text); }

std::string json_string(const std::string& value) {
    std::string out = "\"";
    for (const unsigned char c : value) {
        switch (c) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c >= 0x20) out += static_cast<char>(c);
                break;
        }
    }
    out += '"';
    return out;
}

std::string next_nonce() {
    return "bifrost-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(++nonce_counter);
}

std::string extract_json_string(const std::string& json, const std::string& key) {
    const auto key_pos = json.find("\"" + key + "\"");
    if (key_pos == std::string::npos) return {};
    auto pos = json.find(':', key_pos + key.size() + 2);
    if (pos == std::string::npos) return {};
    do { ++pos; } while (pos < json.size() && std::isspace(static_cast<unsigned char>(json[pos])));
    if (pos >= json.size() || json[pos] != '"') return {};
    std::string out;
    for (++pos; pos < json.size(); ++pos) {
        const char c = json[pos];
        if (c == '"') return out;
        if (c != '\\') {
            out += c;
            continue;
        }
        if (++pos >= json.size()) return {};
        switch (json[pos]) {
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            case '/': out += '/'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            default: return {};
        }
    }
    return {};
}

void disconnect() {
    if (discord_pipe != INVALID_HANDLE_VALUE) {
        CloseHandle(discord_pipe);
        discord_pipe = INVALID_HANDLE_VALUE;
    }
    inbox.clear();
}

bool write_frame(std::uint32_t opcode, const std::string& json) {
    std::string frame(8, '\0');
    const std::uint32_t header[2] = {opcode, static_cast<std::uint32_t>(json.size())};
    std::memcpy(frame.data(), header, sizeof(header));
    frame += json;
    const char* cursor = frame.data();
    std::size_t left = frame.size();
    while (left != 0) {
        DWORD written = 0;
        if (!WriteFile(discord_pipe, cursor, static_cast<DWORD>(left), &written, nullptr) || written == 0) return false;
        cursor += written;
        left -= written;
    }
    return true;
}

bool pump() {
    for (;;) {
        DWORD available = 0;
        if (!PeekNamedPipe(discord_pipe, nullptr, 0, nullptr, &available, nullptr)) return false;
        if (available == 0) return true;
        char chunk[4096];
        DWORD got = 0;
        const DWORD want = available < sizeof(chunk) ? available : static_cast<DWORD>(sizeof(chunk));
        if (!ReadFile(discord_pipe, chunk, want, &got, nullptr) || got == 0) return false;
        inbox.append(chunk, got);
    }
}

bool take_frame(std::uint32_t& opcode, std::string& json) {
    if (inbox.size() < 8) return false;
    std::uint32_t header[2] = {};
    std::memcpy(header, inbox.data(), sizeof(header));
    if (inbox.size() < 8 + static_cast<std::size_t>(header[1])) return false;
    opcode = header[0];
    json = inbox.substr(8, header[1]);
    inbox.erase(0, 8 + static_cast<std::size_t>(header[1]));
    return true;
}

bool handle_events() {
    if (!pump()) return false;
    std::uint32_t opcode = 0;
    std::string json;
    while (take_frame(opcode, json)) {
        if (opcode == kClose) return false;
        if (json.find("\"evt\":\"ERROR\"") != std::string::npos) {
            emit_stderr("Discord error: " + json.substr(0, 400) + "\n");
            continue;
        }
        if (json.find("\"cmd\":\"DISPATCH\"") == std::string::npos) continue;
        if (json.find("\"evt\":\"ACTIVITY_JOIN_REQUEST\"") != std::string::npos) {
            const std::string user = extract_json_string(json, "id");
            if (!user.empty()) emit_stdout("request\t" + user + "\t" + extract_json_string(json, "username") + "\n");
        } else if (json.find("\"evt\":\"ACTIVITY_JOIN\"") != std::string::npos) {
            const std::string secret = extract_json_string(json, "secret");
            if (!secret.empty()) emit_stdout("join\t" + secret + "\n");
        }
    }
    return true;
}

bool connect_discord(const std::string& client_id) {
    HANDLE handle = INVALID_HANDLE_VALUE;
    for (int i = 0; i < 10 && handle == INVALID_HANDLE_VALUE; ++i) {
        const std::wstring path = pipe_base + std::to_wstring(i);
        handle = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
    }
    if (handle == INVALID_HANDLE_VALUE) return false;
    discord_pipe = handle;
    inbox.clear();

    if (!write_frame(kHandshake, "{\"v\":1,\"client_id\":" + json_string(client_id) + "}")) {
        disconnect();
        return false;
    }
    const ULONGLONG deadline = GetTickCount64() + kHandshakeMs;
    std::uint32_t opcode = 0;
    std::string reply;
    for (;;) {
        if (!pump()) {
            disconnect();
            return false;
        }
        if (take_frame(opcode, reply)) break;
        if (GetTickCount64() > deadline) {
            emit_stderr("Discord didn't answer the handshake\n");
            disconnect();
            return false;
        }
        Sleep(10);
    }
    if (opcode == kClose || reply.find("\"evt\":\"ERROR\"") != std::string::npos) {
        emit_stderr("Discord refused the handshake: " + reply.substr(0, 400) + "\n");
        disconnect();
        return false;
    }
    for (const char* event : {"ACTIVITY_JOIN", "ACTIVITY_JOIN_REQUEST"}) {
        const std::string subscribe = std::string("{\"cmd\":\"SUBSCRIBE\",\"evt\":\"") + event +
                                      "\",\"args\":{},\"nonce\":" + json_string(next_nonce()) + "}";
        if (!write_frame(kFrame, subscribe)) {
            disconnect();
            return false;
        }
    }
    emit_stdout("ready\n");
    return true;
}

bool accept_join_request(const std::string& user_id) {
    return write_frame(kFrame, "{\"cmd\":\"SEND_ACTIVITY_JOIN_INVITE\",\"args\":{\"user_id\":" + json_string(user_id) +
                                   "},\"nonce\":" + json_string(next_nonce()) + "}");
}

void register_with_discord(const std::string& client_id, HANDLE game, bool self) {
    wchar_t exe[MAX_PATH * 2] = {};
    DWORD size = static_cast<DWORD>(sizeof(exe) / sizeof(exe[0]));
    if (self) {
        if (!GetModuleFileNameW(nullptr, exe, size)) return;
    } else if (game == nullptr || !QueryFullProcessImageNameW(game, 0, exe, &size)) {
        return;
    }
    const std::wstring id(client_id.begin(), client_id.end());
    const std::wstring key = L"Software\\Classes\\discord-" + id;
    const std::wstring command = L"\"" + std::wstring(exe) + L"\"";
    const std::wstring name = L"URL:Run game " + id + L" protocol";
    auto set = [](const std::wstring& path, const wchar_t* value_name, const std::wstring& value) {
        HKEY handle = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &handle, nullptr) !=
            ERROR_SUCCESS) {
            return;
        }
        RegSetValueExW(handle, value_name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                       static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(handle);
    };
    set(key, nullptr, name);
    set(key, L"URL Protocol", L"");
    set(key + L"\\DefaultIcon", nullptr, exe);
    set(key + L"\\shell\\open\\command", nullptr, command);
}

bool send_activity(const std::string& activity) {
    const std::string command = "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":" + std::to_string(activity_pid) +
                                ",\"activity\":" + activity + "},\"nonce\":" + json_string(next_nonce()) + "}";
    return write_frame(kFrame, command);
}

HANDLE open_parent() {
    const DWORD self = GetCurrentProcessId();
    DWORD parent_id = 0;
    const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return nullptr;
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    for (BOOL ok = Process32FirstW(snapshot, &entry); ok; ok = Process32NextW(snapshot, &entry)) {
        if (entry.th32ProcessID == self) {
            parent_id = entry.th32ParentProcessID;
            break;
        }
    }
    CloseHandle(snapshot);
    if (parent_id == 0) return nullptr;
    const HANDLE parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent_id);
    if (parent == nullptr) return nullptr;
    FILETIME parent_created = {}, self_created = {}, unused1 = {}, unused2 = {}, unused3 = {};
    if (GetProcessTimes(parent, &parent_created, &unused1, &unused2, &unused3) &&
        GetProcessTimes(GetCurrentProcess(), &self_created, &unused1, &unused2, &unused3) &&
        CompareFileTime(&parent_created, &self_created) > 0) {
        CloseHandle(parent);
        return nullptr;
    }
    activity_pid = parent_id;
    return parent;
}

void read_input() {
    const HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    std::string pending;
    char chunk[4096];
    DWORD got = 0;
    while (input != INVALID_HANDLE_VALUE && input != nullptr && ReadFile(input, chunk, sizeof(chunk), &got, nullptr) &&
           got != 0) {
        pending.append(chunk, got);
        std::size_t newline = 0;
        while ((newline = pending.find('\n')) != std::string::npos) {
            std::string line = pending.substr(0, newline);
            pending.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            std::lock_guard<std::mutex> lock(lines_mutex);
            lines.push_back(line);
        }
    }
    input_closed = true;
}

}

static int bridge_main(int argc, wchar_t** argv, bool self) {
    if (argc < 2) {
        emit_stderr("missing Discord client ID\n");
        return 2;
    }
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, argv[1], -1, nullptr, 0, nullptr, nullptr);
    std::vector<char> id_buffer(bytes);
    WideCharToMultiByte(CP_UTF8, 0, argv[1], -1, id_buffer.data(), bytes, nullptr, nullptr);
    const std::string client_id(id_buffer.data());
    const bool test_pipe = argc >= 3;
    if (test_pipe) pipe_base = argv[2];

    activity_pid = GetCurrentProcessId();
    const HANDLE parent = open_parent();
    if (!test_pipe) register_with_discord(client_id, parent, self);
    std::thread(read_input).detach();
    std::vector<std::string> accepts;

    std::string desired;
    bool dirty = false;
    bool quit = false;
    bool warned = false;
    ULONGLONG next_attempt = 0;
    while (!quit) {
        if (parent != nullptr && WaitForSingleObject(parent, 0) == WAIT_OBJECT_0) break;
        bool ended = input_closed;
        {
            std::lock_guard<std::mutex> lock(lines_mutex);
            while (!lines.empty()) {
                const std::string line = lines.front();
                lines.pop_front();
                if (line == "__quit__") {
                    quit = true;
                    break;
                }
                if (line.rfind("accept\t", 0) == 0) {
                    accepts.push_back(line.substr(7));
                    continue;
                }
                desired = line;
                dirty = true;
            }
        }
        if (quit || ended) break;

        if (discord_pipe != INVALID_HANDLE_VALUE && !handle_events()) {
            disconnect();
            dirty = !desired.empty();
        }
        if (dirty && discord_pipe == INVALID_HANDLE_VALUE && desired == "null") dirty = false;
        if (dirty && discord_pipe == INVALID_HANDLE_VALUE && GetTickCount64() >= next_attempt) {
            if (connect_discord(client_id)) {
                warned = false;
            } else {
                next_attempt = GetTickCount64() + kRetryMs;
                if (!warned) emit_stderr("Discord is not running or its IPC pipe is unavailable; retrying\n");
                warned = true;
            }
        }
        if (dirty && discord_pipe != INVALID_HANDLE_VALUE) {
            if (send_activity(desired)) {
                dirty = false;
            } else {
                disconnect();
            }
        }
        if (!accepts.empty() && discord_pipe != INVALID_HANDLE_VALUE) {
            for (const std::string& user : accepts) {
                if (!accept_join_request(user)) {
                    disconnect();
                    break;
                }
            }
            accepts.clear();
        }
        Sleep(kTickMs);
    }

    if (discord_pipe != INVALID_HANDLE_VALUE) {
        send_activity("null");
        Sleep(50);
        disconnect();
    }
    ExitProcess(0);
}

#ifdef BIFROST_BRIDGE_EMBEDDED
extern "C" int bifrost_discord_bridge(int argc, wchar_t** argv) { return bridge_main(argc, argv, true); }
#else
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    return bridge_main(argc, argv, false);
}
#endif
