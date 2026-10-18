#!/bin/bash
# Подсветка клавиатуры и клавиша N на Acer Nitro AN515-45 под Omarchy.
# Запускать от обычного пользователя; пароль sudo спросит сам. Повторный запуск безопасен.
set -euo pipefail

repo=$(dirname "$(readlink -f "$0")")
pkg=acer-wmi-linuwu-dkms-git
kernel=$(uname -r)
kb=/sys/devices/platform/acer-wmi/four_zoned_kb
bindings=$HOME/.config/hypr/bindings.lua

step() { echo -e "\n==> $*"; }
die() {
  echo "Ошибка: $*" >&2
  exit 1
}

((EUID != 0)) || die "запускайте без sudo, от своего пользователя"

model=$(</sys/class/dmi/id/product_name)
if [[ $model != "Nitro AN515-45" && ${1:-} != "--force" ]]; then
  die "это $model, а не Nitro AN515-45. Если уверены, запустите с --force"
fi

step "Зависимости: dkms и заголовки ядра"
sudo pacman -S --needed --noconfirm dkms
if [[ ! -d /usr/lib/modules/$kernel/build ]]; then
  kernel_pkg=$(pacman -Qqo "/usr/lib/modules/$kernel/vmlinuz")
  sudo pacman -S --needed --noconfirm "$kernel_pkg-headers"
fi

step "Системные файлы: патч модуля, хук pacman, правило udev"
sudo install -Dm755 "$repo/system/acer-wmi-an515-45-patch" /usr/local/sbin/acer-wmi-an515-45-patch
sudo install -Dm644 "$repo/system/60-acer-wmi-an515-45.hook" /etc/pacman.d/hooks/60-acer-wmi-an515-45.hook
sudo install -Dm644 "$repo/system/99-acer-kbd-backlight.rules" /etc/udev/rules.d/99-acer-kbd-backlight.rules

step "Модуль ядра $pkg (AUR)"
if ! pacman -Q "$pkg" &>/dev/null; then
  yay -S --needed --noconfirm "$pkg"
fi

# Хук уже патчит исходники до сборки, но пересобираем явно: так результат
# не зависит от того, был ли пакет установлен раньше.
sudo /usr/local/sbin/acer-wmi-an515-45-patch
version=$(pacman -Q "$pkg" | awk '{print $2}')
version=${version%-*}
sudo dkms build --force -m acer-wmi-linuwu -v "$version" -k "$kernel"
sudo dkms install --force -m acer-wmi-linuwu -v "$version" -k "$kernel"

step "Перезагрузка модуля"
sudo udevadm control --reload
sudo rmmod acer_wmi 2>/dev/null || true
sudo modprobe acer_wmi
sudo udevadm settle
[[ -w $kb/per_zone_mode ]] || die "нет доступа на запись в $kb — модуль или правило udev не сработали"

step "Скрипт kbd-backlight и хуки Omarchy: после загрузки и при смене темы"
install -Dm755 "$repo/bin/kbd-backlight" "$HOME/.local/bin/kbd-backlight"
install -Dm755 "$repo/hooks/kbd-backlight-restore" "$HOME/.config/omarchy/hooks/post-boot.d/kbd-backlight-restore"
install -Dm755 "$repo/hooks/kbd-backlight-theme" "$HOME/.config/omarchy/hooks/theme-set.d/kbd-backlight-theme"

step "Клавиша N в Hyprland"
if [[ ! -f $bindings ]]; then
  echo "Нет $bindings — привязку добавьте вручную (см. docs/guide.md)"
elif grep -q 'kbd-backlight next' "$bindings" && grep -q 'kbd-backlight prev' "$bindings"; then
  echo "Привязки уже есть"
else
  cp "$bindings" "$bindings.bak.$(date +%s)"
  sed -i '/^-- Клавиша N (NitroSense)/d; /kbd-backlight \(next\|prev\)/d' "$bindings"
  cat >>"$bindings" <<'LUA'

-- Клавиша N (NitroSense): следующий цвет подсветки клавиатуры, с Shift — предыдущий.
o.bind("XF86Presentation", "Keyboard backlight color", os.getenv("HOME") .. "/.local/bin/kbd-backlight next")
o.bind("SHIFT + XF86Presentation", "Keyboard backlight previous color", os.getenv("HOME") .. "/.local/bin/kbd-backlight prev")
LUA
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null
    hyprctl configerrors
  fi
fi

"$HOME/.local/bin/kbd-backlight" restore || true

step "Готово. Нажмите клавишу N, чтобы сменить цвет."
