#!/bin/bash
# Убирает всё, что поставил install.sh. Модуль ядра удаляется только с --purge.
set -euo pipefail

bindings=$HOME/.config/hypr/bindings.lua

((EUID != 0)) || {
  echo "Запускайте без sudo, от своего пользователя" >&2
  exit 1
}

rm -f "$HOME/.local/bin/kbd-backlight" \
  "$HOME/.config/omarchy/hooks/post-boot.d/kbd-backlight-restore" \
  "$HOME/.config/omarchy/hooks/theme-set.d/kbd-backlight-theme"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/kbd-backlight"

if [[ -f $bindings ]] && grep -q 'kbd-backlight' "$bindings"; then
  cp "$bindings" "$bindings.bak.$(date +%s)"
  sed -i '/^-- Клавиша N (NitroSense)/d; /kbd-backlight next/d' "$bindings"
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl reload >/dev/null
fi

sudo rm -f /usr/local/sbin/acer-wmi-an515-45-patch \
  /etc/pacman.d/hooks/60-acer-wmi-an515-45.hook \
  /etc/udev/rules.d/99-acer-kbd-backlight.rules
sudo udevadm control --reload

if [[ ${1:-} == "--purge" ]]; then
  sudo pacman -Rns --noconfirm acer-wmi-linuwu-dkms-git
  sudo rmmod acer_wmi 2>/dev/null || true
  sudo modprobe acer_wmi
  echo "Модуль удалён, загружен штатный acer_wmi."
else
  echo "Модуль ядра оставлен. Чтобы удалить и его: ./uninstall.sh --purge"
fi
