// VidCoderPortable.exe: Windows-native launcher for a source-patched VidCoder build.
// Bundled original application and settings are not modified on the user's machine.
// License: GPL-2.0; see Other/License for VidCoder upstream license.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <iterator>
#include <filesystem>

static std::wstring qarg(const std::wstring& s) {
    if (s.empty()) return L"\"\"";
    if (s.find_first_of(L" \t\n\v\"") == std::wstring::npos) return s;
    std::wstring out = L"\"";
    unsigned backslashes = 0;
    for (wchar_t ch : s) {
        if (ch == L'\\') { ++backslashes; continue; }
        if (ch == L'"') { out.append(backslashes * 2 + 1, L'\\'); out.push_back(ch); backslashes = 0; continue; }
        out.append(backslashes, L'\\'); backslashes = 0; out.push_back(ch);
    }
    out.append(backslashes * 2, L'\\'); out.push_back(L'"');
    return out;
}
static void error(const std::wstring& msg) {
    MessageBoxW(nullptr, msg.c_str(), L"VidCoder Portable", MB_OK | MB_ICONERROR);
}
static bool is_file(const std::wstring& p) {
    DWORD a = GetFileAttributesW(p.c_str());
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}
static bool mkdirs(const std::wstring& p) {
    std::error_code ec;
    std::filesystem::create_directories(p, ec);
    return !ec && std::filesystem::is_directory(p);
}
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    // Prevent two launcher instances from touching the same portable data simultaneously.
    HANDLE lock = CreateMutexW(nullptr, TRUE, L"Local\\VidCoderPortableLauncher-Mutex");
    if (!lock || GetLastError() == ERROR_ALREADY_EXISTS) {
        error(L"VidCoder Portable is already launching or running. Close it first.");
        if (lock) CloseHandle(lock);
        return 2;
    }
    wchar_t exePath[32768] = {};
    DWORD len = GetModuleFileNameW(nullptr, exePath, static_cast<DWORD>(std::size(exePath)));
    if (len == 0 || len >= std::size(exePath)) {
        error(L"Cannot identify the portable launcher location.");
        CloseHandle(lock); return 3;
    }
    std::wstring location(exePath);
    auto slash = location.find_last_of(L"\\/");
    if (slash == std::wstring::npos) { error(L"Invalid launcher path."); CloseHandle(lock); return 4; }
    std::wstring root = location.substr(0, slash);
    std::wstring app = root + L"\\App";
    std::wstring program = app + L"\\VidCoder.exe";
    std::wstring data = root + L"\\Data";
    std::wstring settings = data + L"\\Settings";
    std::wstring temp = data + L"\\Temp";
    std::wstring roaming = data + L"\\Roaming";
    std::wstring local = data + L"\\Local";
    if (!is_file(program) || !is_file(app + L"\\VidCoderCommon.dll")) {
        error(L"Missing VidCoder program files. Keep VidCoderPortable.exe and App\\ together.");
        CloseHandle(lock); return 5;
    }
    // Check the app's own global single-instance mutex before starting our process.
    HANDLE other = OpenMutexW(SYNCHRONIZE, FALSE, L"VidCoderInstanceMutex");
    if (other) {
        CloseHandle(other);
        error(L"Another VidCoder instance is already running. Close it before starting VidCoder Portable to avoid mixed settings.");
        CloseHandle(lock); return 6;
    }
    if (!mkdirs(settings) || !mkdirs(temp) || !mkdirs(roaming) || !mkdirs(local)) {
        error(L"Cannot create portable Data folders. Move this package to a writable folder or drive.");
        CloseHandle(lock); return 7;
    }
    // Recover from a previous forced shutdown: clear only our own temporary folder.
    // Never delete Windows-wide Temp, AppData, or other applications' settings.
    std::error_code previousTempError;
    std::filesystem::remove_all(temp, previousTempError);
    if (!mkdirs(temp)) {
        error(L"Cannot prepare the portable temporary directory.");
        CloseHandle(lock); return 10;
    }
    // These environment changes apply only to this process and its VidCoder child processes.
    // Source patches make AppFolder/SQLite use settings regardless of Windows Known Folder APIs.
    if (!SetEnvironmentVariableW(L"VIDCODER_PORTABLE_DATA_DIR", settings.c_str()) ||
        !SetEnvironmentVariableW(L"TEMP", temp.c_str()) ||
        !SetEnvironmentVariableW(L"TMP", temp.c_str()) ||
        !SetEnvironmentVariableW(L"APPDATA", roaming.c_str()) ||
        !SetEnvironmentVariableW(L"LOCALAPPDATA", local.c_str())) {
        error(L"Could not set isolated portable environment variables.");
        CloseHandle(lock); return 8;
    }
    std::wstring command = qarg(program);
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv) {
        for (int i = 1; i < argc; ++i) command += L" " + qarg(argv[i]);
        LocalFree(argv);
    }
    std::vector<wchar_t> mutableCommand(command.begin(), command.end());
    mutableCommand.push_back(L'\0');
    STARTUPINFOW si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};
    BOOL started = CreateProcessW(program.c_str(), mutableCommand.data(), nullptr, nullptr,
                                  FALSE, 0, nullptr, app.c_str(), &si, &pi);
    if (!started) {
        DWORD code = GetLastError();
        error(L"Could not launch VidCoder. Windows error: " + std::to_wstring(code));
        CloseHandle(lock); return 9;
    }
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    // Only clean our own temporary directory; never edit real host AppData or ProgramData.
    // Leftover temp from forced exits is also inside Data, not in the Windows user profile.
    std::error_code cleanupError;
    std::filesystem::remove_all(temp, cleanupError);
    CloseHandle(lock);
    return static_cast<int>(code);
}
