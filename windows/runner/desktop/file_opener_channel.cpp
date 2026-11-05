#include "file_opener_channel.h"

#include <windows.h>

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <string>

namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/file_opener";

// `MAX_PATH` is 260, but a long-path aware process accepts up to 32767
// characters. Anything longer cannot be a path this app produced; rejecting it
// here keeps the wide conversion below bounded.
constexpr size_t kMaxPathLength = 32767;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()),
                                       nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

// `path` is a filesystem path, never a `content://` document URI: the Dart
// side resolves those through the SAF tree and never asks this channel.
bool IsAbsolutePath(const std::wstring& path) {
  if (path.size() >= 2) {
    const wchar_t first = path[0];
    const wchar_t second = path[1];
    const bool drive = ((first >= L'A' && first <= L'Z') ||
                        (first >= L'a' && first <= L'z')) &&
                       second == L':';
    if (drive) {
      return true;
    }
  }
  // UNC (\\server\share) and the \\?\ long-path forms.
  return path.size() >= 2 && path[0] == L'\\' && path[1] == L'\\';
}

struct PathCheck {
  bool ok = false;
  std::string code;
  std::string message;
};

PathCheck ValidatePath(const std::wstring& path, bool want_directory) {
  PathCheck check;
  if (path.empty()) {
    check.code = "INVALID_PATH";
    check.message = "Path is empty";
    return check;
  }
  if (path.size() > kMaxPathLength) {
    check.code = "INVALID_PATH";
    check.message = "Path is too long";
    return check;
  }
  if (!IsAbsolutePath(path)) {
    // A relative path would be resolved against the install directory, which
    // is not where the user means.
    check.code = "INVALID_PATH";
    check.message = "Path is not absolute";
    return check;
  }

  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    check.code = "INVALID_PATH";
    check.message = "Path does not exist";
    return check;
  }
  const bool is_directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  if (want_directory && !is_directory) {
    check.code = "INVALID_PATH";
    check.message = "Path is not a folder";
    return check;
  }
  if (!want_directory && is_directory) {
    check.code = "INVALID_PATH";
    check.message = "Path is a folder, not a file";
    return check;
  }
  check.ok = true;
  return check;
}

// ShellExecuteW returns a value > 32 on success; anything at or below 32 is a
// documented error code (there is no GetLastError for this API).
bool ShellOpen(const std::wstring& verb, const std::wstring& path) {
  const HINSTANCE result = ShellExecuteW(nullptr, verb.c_str(), path.c_str(),
                                         nullptr, nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(result) > 32;
}

void FinishOpen(
    const std::wstring& path,
    bool want_directory,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const PathCheck check = ValidatePath(path, want_directory);
  if (!check.ok) {
    result->Error(check.code, check.message);
    return;
  }

  bool opened = false;
  if (want_directory) {
    // "explore" selects the folder instead of merely opening Explorer; not
    // every shell registers it (a stripped-down Explorer replacement does
    // not), so "open" is the fallback.
    opened = ShellOpen(L"explore", path) || ShellOpen(L"open", path);
  } else {
    opened = ShellOpen(L"open", path);
  }

  if (!opened) {
    result->Error("OPEN_FAILED", want_directory
                      ? "No file manager accepted this folder"
                      : "No application accepted this file");
    return;
  }
  result->Success(flutter::EncodableValue(true));
}

}  // namespace

FileOpenerChannel::FileOpenerChannel(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

FileOpenerChannel::~FileOpenerChannel() = default;

void FileOpenerChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Dart sends the path as the single argument. A map with "path" is also
  // accepted so a future caller can add options without a breaking change.
  std::string path;
  // EncodableValue is the variant itself, so the argument pointer is used as is;
  // std::get_if<EncodableValue> cannot compile against it.
  const flutter::EncodableValue* arguments = call.arguments();
  if (arguments != nullptr && !arguments->IsNull()) {
    if (const auto* value = std::get_if<std::string>(arguments)) {
      path = *value;
    } else if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
      const auto it = map->find(flutter::EncodableValue(std::string("path")));
      if (it != map->end()) {
        if (const auto* path_value = std::get_if<std::string>(&it->second)) {
          path = *path_value;
        }
      }
    }
  }

  const std::wstring wide_path = Utf8ToWide(path);
  if (call.method_name() == "openFile") {
    FinishOpen(wide_path, /*want_directory=*/false, std::move(result));
    return;
  }
  if (call.method_name() == "openFolder") {
    FinishOpen(wide_path, /*want_directory=*/true, std::move(result));
    return;
  }
  result->NotImplemented();
}
