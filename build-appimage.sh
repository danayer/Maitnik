#!/bin/bash
# Скрипт для создания AppImage пакета для программы Maitnik

# Проверка наличия необходимых утилит
command -v wget >/dev/null 2>&1 || { echo "Ошибка: wget не установлен"; exit 1; }
command -v valac >/dev/null 2>&1 || { echo "Ошибка: valac не установлен"; exit 1; }
command -v pkg-config >/dev/null 2>&1 || { echo "Ошибка: pkg-config не установлен"; exit 1; }
pkg-config --exists gtk4 || { echo "Ошибка: GTK4 не установлен"; exit 1; }

# Компиляция программы
echo "Компиляция программы..."
make clean
make

# Создание AppDir структуры
APPDIR="Maitnik.AppDir"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/lib"

# Копирование бинарного файла и установка правильных прав
cp maitnik "$APPDIR/usr/bin/"
chmod 755 "$APPDIR/usr/bin/maitnik"

# Создание .desktop файла
cat > "$APPDIR/usr/share/applications/maitnik.desktop" << EOF
[Desktop Entry]
Name=Маятник
Comment=Измерение скорости тела баллистическим маятником
Exec=maitnik
Icon=maitnik
Terminal=false
Type=Application
Categories=Education;Science;
EOF

# Копирование иконки (если она есть)
if [ -f "maitnik.svg" ]; then
    cp maitnik.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
elif [ -f "maitnik.png" ]; then
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
    cp maitnik.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/maitnik.png"
else
    # Создаем простую иконку, если нет готовой
    echo "Создание простой иконки..."
    cat > "$APPDIR/usr/share/icons/hicolor/scalable/apps/maitnik.svg" << EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="256" height="256" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
  <circle cx="128" cy="128" r="120" fill="#3584e4" />
  <text x="128" y="128" font-family="Sans" font-size="40" text-anchor="middle" fill="white">Маятник</text>
</svg>
EOF
fi

# Создаем AppRun файл с исправленной обработкой прав
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
# Определение путей
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
BINARY="${HERE}/usr/bin/maitnik"

# Устанавливаем переменные окружения
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"

# Проверяем доступ к портам Arduino без прав root
ACCESS=0
for PORT in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB0 /dev/ttyUSB1; do
    if [ -w "$PORT" ] 2>/dev/null; then
        ACCESS=1
        break
    fi
done

# Запускаем с повышением привилегий только при необходимости
if [ "$ACCESS" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    # Пробуем различные способы повышения привилегий
    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$BINARY" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        exec sudo "$BINARY" "$@" 
    elif command -v gksudo >/dev/null 2>&1; then
        exec gksudo "$BINARY" "$@"
    else
        # Если нет доступных способов, выводим сообщение
        echo "Внимание: для доступа к Arduino требуются права администратора"
        echo "Запустите программу вручную с sudo или настройте права доступа к портам"
        echo "Инструкции в README.md: раздел 'Настройка прав доступа к Arduino'"
        
        # Все равно пытаемся запустить
        exec "$BINARY" "$@"
    fi
else
    # Если у нас уже есть права, запускаем напрямую
    exec "$BINARY" "$@"
fi
EOF
chmod +x "$APPDIR/AppRun"

# Создание простого иконочного файла для AppImage
echo "Создание файла иконки для AppImage..."
ln -sf usr/share/icons/hicolor/scalable/apps/maitnik.svg "$APPDIR/maitnik.svg"
ln -sf usr/share/applications/maitnik.desktop "$APPDIR/maitnik.desktop"

# Загрузка и использование appimagetool
echo "Загрузка appimagetool..."
wget -c https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
chmod +x appimagetool

# Создание AppImage
echo "Создание AppImage..."
./appimagetool "$APPDIR" Maitnik-x86_64.AppImage

# Очистка
echo "Очистка временных файлов..."
rm -rf "$APPDIR" appimagetool

echo "AppImage создан: Maitnik-x86_64.AppImage"