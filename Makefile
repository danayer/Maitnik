# Makefile для сборки программы Maitnik на Vala с GTK 4

# Компилятор и флаги
VALAC = valac
VALAFLAGS = --pkg gtk4 --pkg posix -X -lm

# Имя исполняемого файла
APP_NAME = maitnik

# Исходные файлы
SRC_FILES = maitnik.vala

# Директории установки
PREFIX = /usr/local
BIN_DIR = $(PREFIX)/bin
DESKTOP_DIR = $(PREFIX)/share/applications
ICON_DIR = $(PREFIX)/share/icons/hicolor/scalable/apps

# Основная цель - сборка приложения
all: $(APP_NAME)

# Компиляция исходных файлов в исполняемый файл
$(APP_NAME): $(SRC_FILES)
	$(VALAC) $(VALAFLAGS) -o $@ $<

# Запуск программы
run: $(APP_NAME)
	./$(APP_NAME)

# Запуск с sudo (для доступа к последовательному порту)
run-sudo: $(APP_NAME)
	sudo ./$(APP_NAME)

# Очистка директории от сгенерированных файлов
clean:
	rm -f $(APP_NAME)
	rm -f *.c
	rm -f *.o
	rm -f *.h

# Установка приложения в систему
install: $(APP_NAME)
	# Создаем директории, если они не существуют
	mkdir -p $(DESTDIR)$(BIN_DIR)
	mkdir -p $(DESTDIR)$(DESKTOP_DIR)
	
	# Установка исполняемого файла
	install -m 755 $(APP_NAME) $(DESTDIR)$(BIN_DIR)

	# Создание .desktop файла для запуска из меню
	echo "[Desktop Entry]" > $(APP_NAME).desktop
	echo "Name=Маятник" >> $(APP_NAME).desktop
	echo "Comment=Измерение скорости тела баллистическим маятником" >> $(APP_NAME).desktop
	echo "Exec=$(BIN_DIR)/$(APP_NAME)" >> $(APP_NAME).desktop
	echo "Terminal=false" >> $(APP_NAME).desktop
	echo "Type=Application" >> $(APP_NAME).desktop
	echo "Categories=Education;Science;" >> $(APP_NAME).desktop
	install -m 644 $(APP_NAME).desktop $(DESTDIR)$(DESKTOP_DIR)/

# Удаление приложения из системы
uninstall:
	rm -f $(DESTDIR)$(BIN_DIR)/$(APP_NAME)
	rm -f $(DESTDIR)$(DESKTOP_DIR)/$(APP_NAME).desktop

# Указание фиктивных целей
.PHONY: all run run-sudo clean install uninstall

# Отладочная сборка с дополнительной информацией
debug: VALAFLAGS += -g --save-temps
debug: $(APP_NAME)

# Оптимизированная сборка
release: VALAFLAGS += -X -O2
release: $(APP_NAME)

# Создание пакета для установки (опционально)
package:
	mkdir -p package/$(APP_NAME)
	cp $(APP_NAME) package/$(APP_NAME)/
	cp $(APP_NAME).desktop package/$(APP_NAME)/
	cd package && tar -czf $(APP_NAME).tar.gz $(APP_NAME)
	rm -rf package/$(APP_NAME)
