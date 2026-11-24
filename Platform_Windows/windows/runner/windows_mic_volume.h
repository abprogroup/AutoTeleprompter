#ifndef RUNNER_WINDOWS_MIC_VOLUME_H_
#define RUNNER_WINDOWS_MIC_VOLUME_H_

#include <optional>
#include <string>

struct WindowsMicVolumeState {
  bool available = false;
  int volume_percent = 0;
  bool muted = false;
  std::string device_name;
  std::string error;
};

WindowsMicVolumeState GetWindowsMicVolume(const std::string& preferred_label);

WindowsMicVolumeState SetWindowsMicVolume(const std::string& preferred_label,
                                          int volume_percent,
                                          std::optional<bool> muted);

#endif  // RUNNER_WINDOWS_MIC_VOLUME_H_
