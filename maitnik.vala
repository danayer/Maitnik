/*
 * Программа для измерения скорости тела баллистическим маятником
 * Использует GTK 4 и последовательный порт для получения данных с Arduino
 */
using Gtk;
using GLib;

// Основной класс приложения, содержащий все необходимые данные
public class MaitnikApp : Gtk.Application {
    // Константы для настроек приложения
    private const int SAMPLE_RATE = 10;            // Количество точек в секунду
    private const int MAX_MEASUREMENT_TIME = 30;   // Максимальное время измерения в секундах
    private const int MAX_SAMPLES = MAX_MEASUREMENT_TIME * SAMPLE_RATE; // Максимальное количество точек

    // Главное окно и виджеты
    private Gtk.ApplicationWindow window;
    private Gtk.Label angle_label;                // Метка для текущего угла
    private Gtk.Label max_angle_label;            // Метка для максимального/минимального угла
    private Gtk.Label cursor_label;               // Метка для значения под курсором
    private Gtk.DrawingArea drawing_area;         // Область для графика
    
    // Данные измерений и состояние
    private int serial_fd = -1;                   // Дескриптор последовательного порта
    private bool is_measuring = false;            // Флаг измерения
    private float[] angle_data = {};              // Массив данных угла
    private float max_angle = -float.INFINITY;    // Максимальный угол (исправлено)
    private float min_angle = float.INFINITY;     // Минимальный угол (исправлено)
    private double cursor_x = -1;                 // Позиция курсора X
    // Удалено неиспользуемое поле start_time
    
    // Перенесенные из метода update_angle статические переменные
    private char[] line_buffer = new char[512];   // Буфер для обработки строк с порта
    private int line_pos = 0;                     // Текущая позиция в буфере
    
    // Главные циклы для диалогов
    private static MainLoop? main_loop = null;
    private static MainLoop? device_error_main_loop = null;
    
    // Добавляем переменную для хранения последней позиции курсора
    private double last_cursor_x = -1;    // На уровне класса вместо статической переменной

    // Конструктор приложения
    public MaitnikApp() {
        Object(application_id: "org.maitnik.app", 
               flags: ApplicationFlags.DEFAULT_FLAGS);
    }
    
    // Метод активации приложения (вызывается при запуске)
    protected override void activate() {
        // Создаем главное окно с современным стилем
        window = new Gtk.ApplicationWindow(this);
        window.title = "Измерение скорости тела баллистическим маятником";
        window.default_width = 800;
        window.default_height = 600;
        
        // Основной контейнер с большими отступами
        var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
        main_box.margin_start = 24;
        main_box.margin_end = 24;
        main_box.margin_top = 24;
        main_box.margin_bottom = 24;

        // Верхняя секция с информацией и кнопками
        var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        header_box.add_css_class("header-section");
        
        // Отображение угла в реальном времени с современным стилем
        angle_label = new Gtk.Label("Угол в реальном времени: 0°");
        angle_label.add_css_class("title-4");
        angle_label.hexpand = true;
        angle_label.halign = Gtk.Align.START;
        
        // Блок кнопок управления
        var control_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        control_box.halign = Gtk.Align.END;
        
        // Стилизованные кнопки
        var reset_button = new Gtk.Button.with_label("Настройка");
        reset_button.add_css_class("suggested-action");
        
        var measure_button = new Gtk.Button.with_label("Пуск");
        measure_button.add_css_class("suggested-action");
        
        control_box.append(reset_button);
        control_box.append(measure_button);
        
        header_box.append(angle_label);
        header_box.append(control_box);
        
        // Область графика с рамкой
        var graph_frame = new Gtk.Frame(null);
        graph_frame.add_css_class("view");
        graph_frame.set_size_request(-1, 400);
        
        // Создаем область для рисования графика
        drawing_area = new Gtk.DrawingArea();
        drawing_area.hexpand = true;
        drawing_area.vexpand = true;
        drawing_area.set_draw_func(draw_graph);
        drawing_area.can_target = true;
        
        graph_frame.child = drawing_area;
        
        // Секция статистики
        var stats_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        stats_box.add_css_class("stats-section");
        stats_box.set_size_request(-1, 80); // Фиксируем минимальную высоту
        
        max_angle_label = new Gtk.Label("Максимальный угол: 0.00°, Минимальный угол: 0.00°");
        cursor_label = new Gtk.Label("Угол: 0.00°");
        
        max_angle_label.add_css_class("stats-label");
        cursor_label.add_css_class("stats-label");
        
        max_angle_label.halign = Gtk.Align.START;
        cursor_label.halign = Gtk.Align.START;
        
        // Блок операций с файлами
        var file_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        file_box.halign = Gtk.Align.END;
        
        var save_button = new Gtk.Button.with_label("Сохранить");
        var load_button = new Gtk.Button.with_label("Загрузить");
        
        save_button.add_css_class("suggested-action");
        load_button.add_css_class("suggested-action");
        
        file_box.append(load_button);
        file_box.append(save_button);
        
        // Добавляем все секции в основной контейнер
        main_box.append(header_box);
        main_box.append(graph_frame);
        stats_box.append(max_angle_label);
        stats_box.append(cursor_label);
        stats_box.append(file_box);
        main_box.append(stats_box);
        
        // Применяем CSS стили
        apply_css_styles();
        
        // Подключаем обработчики сигналов к кнопкам
        reset_button.clicked.connect(reset_angle);
        measure_button.clicked.connect(() => on_measure_button_clicked(measure_button));
        save_button.clicked.connect(on_save_clicked);
        load_button.clicked.connect(on_load_clicked);
        
        // Контроллер для отслеживания движения мыши над графиком
        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect(on_motion_notify);
        drawing_area.add_controller(motion);
        
        // Устанавливаем главный контейнер как дочерний для окна
        window.set_child(main_box);
        window.present();
        
        // Настраиваем таймер для периодических обновлений данных
        Timeout.add(100, update_angle);
    }

    // Функция для открытия последовательного порта
    private int open_serial_port(string port_name) {
        // Открываем порт для чтения и записи без управляющего терминала
        int fd = Posix.open(port_name, Posix.O_RDWR | Posix.O_NOCTTY);
        if (fd < 0) {
            print("Ошибка открытия %s: %s\n", port_name, Posix.strerror(Posix.errno));
            return -1;
        }

        // Настраиваем параметры порта
        Posix.termios tty = {};
        if (Posix.tcgetattr(fd, out tty) != 0) {
            return -1;
        }

        // Устанавливаем скорость передачи 9600 бод
        Posix.cfsetospeed(ref tty, Posix.B9600);
        Posix.cfsetispeed(ref tty, Posix.B9600);

        // Настраиваем контроль режима
        tty.c_cflag |= (Posix.CLOCAL | Posix.CREAD);
        tty.c_cflag &= ~Posix.CSIZE;
        tty.c_cflag |= Posix.CS8;          // 8 бит данных
        tty.c_cflag &= ~Posix.PARENB;      // без проверки четности
        tty.c_cflag &= ~Posix.CSTOPB;      // один стоп-бит

        // Настраиваем локальные режимы - неканонический режим
        tty.c_lflag &= ~Posix.ICANON;      // чтение по мере поступления байтов
        tty.c_lflag &= ~Posix.ECHO;        // не отображать вводимые символы
        tty.c_lflag &= ~Posix.ECHOE;       // не отображать удаление символов
        tty.c_lflag &= ~Posix.ECHONL;      // не отображать символы новой строки
        tty.c_lflag &= ~Posix.ISIG;        // не генерировать сигналы

        // Применяем настройки
        if (Posix.tcsetattr(fd, Posix.TCSANOW, tty) != 0) {
            return -1;
        }

        return fd;
    }

    // Сбрасывает измерение угла на устройстве
    private void reset_angle() {
        if (serial_fd != -1) {
            var data = "n".data;
            Posix.write(serial_fd, data, 1);
        }
    }

    // Обновляет данные с последовательного порта
    private bool update_angle() {
        char[] buffer = new char[256];

        // Проверка, достигли ли мы 30 секунд данных
        if (is_measuring && angle_data.length >= MAX_SAMPLES) {
            is_measuring = false;
            
            // Находим кнопку измерения через родителя и устанавливаем текст "Пуск"
            var button = find_button_with_label("Стоп");
            if (button != null) {
                button.label = "Пуск";
                print("Измерение автоматически остановлено, кнопка обновлена на 'Пуск'\n");
            } else {
                print("Внимание: не удалось найти кнопку 'Стоп' для обновления\n");
            }
            
            // Обновляем финальные значения
            var max_min_text = "Максимальный угол: %.2f°, Минимальный угол: %.2f°".printf(max_angle, min_angle);
            max_angle_label.set_text(max_min_text);
        }

        // Чтение данных из последовательного порта
        ssize_t bytes_read = Posix.read(serial_fd, buffer, buffer.length - 1);
        if (bytes_read > 0) {
            // Добавляем завершающий нуль для вывода
            buffer[bytes_read] = '\0';
            
            // Отладочный вывод - показываем что пришло с порта
            print("Получено с порта (%ld байт): %s\n", bytes_read, (string)buffer);
            
            // Обрабатываем полученные данные
            for (int i = 0; i < bytes_read; i++) {
                if (buffer[i] == '\n') {
                    line_buffer[line_pos] = '\0';
                    
                    // Добавляем отладочный вывод
                    print("Обрабатываем строку: '%s'\n", (string)line_buffer);
                    
                    // Извлекаем числа из строки без привязки к конкретному формату
                    float angle_value = 0.0f;
                    if (extract_number_from_string((string)line_buffer, out angle_value)) {
                        print("Успешно распознан угол: %.2f\n", angle_value);
                        var angle_text = "Угол в реальном времени: %.2f°".printf(angle_value);
                        angle_label.set_text(angle_text);
                        
                        if (is_measuring) {
                            // Сохраняем данные в массив
                            angle_data += angle_value;
                            if (angle_value > max_angle) max_angle = angle_value;
                            if (angle_value < min_angle) min_angle = angle_value;
                            
                            var max_min_text = "Максимальный угол: %.2f°, Минимальный угол: %.2f°".printf(
                                max_angle, min_angle);
                            max_angle_label.set_text(max_min_text);
                            
                            drawing_area.queue_draw();
                        }
                    } else {
                        print("Не удалось найти число в строке\n");
                    }
                    
                    line_pos = 0;
                } else if (line_pos < line_buffer.length - 1) {
                    line_buffer[line_pos++] = buffer[i];
                }
            }
        } else if (bytes_read == 0) {
            print("Соединение закрыто или нет данных\n");
        } else {
            print("Ошибка при чтении: %s\n", Posix.strerror(Posix.errno));
        }
        return Source.CONTINUE;
    }

    // Исправленная функция для извлечения числа из строки
    private bool extract_number_from_string(string input, out float result) {
        result = 0.0f;
        
        print("Обрабатываем строку длиной %d символов\n", input.length);
        
        // Простой поиск числа для строк с известной структурой
        if (input.contains("Угол:")) {
            // Разделяем по двоеточию и берем правую часть
            string[] parts = input.split(":");
            if (parts.length >= 2) {
                // Берем вторую часть после разделения (после двоеточия)
                string value_part = parts[1].strip();
                print("Извлеченная часть после ':': '%s'\n", value_part);
                
                // Конвертируем в число напрямую
                double temp = 0.0;
                if (double.try_parse(value_part, out temp)) {
                    result = (float)temp;
                    print("✓ Успешное преобразование в число: %f\n", result);
                    return true;
                } else {
                    print("✗ Не удалось преобразовать '%s' в число\n", value_part);
                }
            }
        }
        
        // Если простой метод не сработал, используем регулярные выражения
        try {
            Regex regex = new Regex("(\\d+\\.\\d+)");
            MatchInfo match_info;
            
            if (regex.match(input, 0, out match_info)) {
                string number_str = match_info.fetch(1);
                print("Найдено с помощью регулярного выражения: '%s'\n", number_str);
                
                // Преобразуем в число
                double temp = 0.0;
                if (double.try_parse(number_str, out temp)) {
                    result = (float)temp;
                    print("✓ Успешное преобразование в число (regex): %f\n", result);
                    return true;
                }
            }
        } catch (RegexError e) {
            print("Ошибка регулярного выражения: %s\n", e.message);
        }
        
        // Третий способ - поиск последовательностей цифр
        StringBuilder sb = new StringBuilder();
        bool has_digit = false;
        bool has_decimal = false;
        
        for (int i = 0; i < input.length; i++) {
            char c = input[i];
            // Добавляем ASCII коды для отладки
            if (i < 30) { // Только первые 30 символов для краткости
                print("    Символ[%d]: '%c' (код: %d)\n", i, c, (int)c);
            }
            
            if (c.isdigit()) {
                sb.append_c(c);
                has_digit = true;
            } else if (c == '.' && !has_decimal && has_digit) {
                sb.append_c(c);
                has_decimal = true;
            }
        }
        
        // Проверяем, нашли ли мы число
        if (has_digit) {
            string num_str = sb.str;
            print("Собрано число: '%s'\n", num_str);
            
            double temp = 0.0;
            if (double.try_parse(num_str, out temp)) {
                result = (float)temp;
                print("✓ Успешное преобразование (сборка): %f\n", result);
                return true;
            }
        }
        
        print("! Не удалось извлечь число из строки\n");
        return false;
    }

    // Находит кнопку "Пуск"/"Стоп" среди виджетов
    private Gtk.Widget? find_measure_button() {
        unowned Gtk.Widget? parent = drawing_area.get_parent();
        if (parent == null) return null;
        
        unowned Gtk.Widget? child = parent.get_first_child();
        while (child != null) {
            if (child is Gtk.Button) {
                var label = ((Gtk.Button)child).label;
                if (label == "Стоп" || label == "Пуск") {
                    return child;
                }
            }
            child = child.get_next_sibling();
        }
        return null;
    }

    // Обработчик нажатия кнопки измерения
    private void on_measure_button_clicked(Gtk.Button button) {
        is_measuring = !is_measuring;
        if (is_measuring) {
            // Сбрасываем предыдущие данные
            angle_data = {};
            max_angle = -float.INFINITY;
            min_angle = float.INFINITY;
            button.label = "Стоп";
            cursor_label.set_text("");
            max_angle_label.set_text("Максимальный угол: 0.00°, Минимальный угол: 0.00°");
        } else {
            button.label = "Пуск";
        }
        
        drawing_area.queue_draw();
    }

    // Обработчик движения мыши над графиком - исправленная версия
    private void on_motion_notify(Gtk.EventControllerMotion controller, double x, double y) {
        // Игнорируем незначительные движения курсора (меньше 2 пикселей)
        if (Math.fabs(x - last_cursor_x) < 2.0)
            return;
        
        // Обновляем позицию только при значимом изменении
        cursor_x = x;
        last_cursor_x = x;
        
        // Ограничиваем частоту перерисовок через активную область
        if (drawing_area is Gtk.Widget && drawing_area.get_mapped()) {
            // В GTK4 нет метода queue_draw_area, используем полную перерисовку
            // но с задержкой, чтобы избежать лишних перерисовок
            drawing_area.queue_draw();
            
            // Обновляем текст в отдельном потоке после небольшой задержки
            // чтобы избежать лишних перерисовок при быстром движении мыши
            Timeout.add(50, () => {
                update_cursor_label();
                return Source.REMOVE;
            });
        }
    }

    // Отдельный метод для обновления метки с информацией о курсоре
    private void update_cursor_label() {
        if (cursor_x < 0 || angle_data.length == 0) {
            cursor_label.set_text("");
            return;
        }

        // Проверяем, что курсор находится в допустимой области графика
        int margin_left = 80;
        int margin_right = 40;
        int width = drawing_area.get_width();
        
        if (cursor_x >= margin_left && cursor_x <= width - margin_right) {
            float time_fraction = (float)((cursor_x - margin_left) / (width - margin_left - margin_right));
            float time_seconds = time_fraction * MAX_MEASUREMENT_TIME;
            
            int expected_points = (int)(time_seconds * SAMPLE_RATE);
            if (expected_points < angle_data.length) {
                float angle = angle_data[expected_points];
                cursor_label.set_text("Угол: %.2f° (%.1f сек)".printf(angle, time_seconds));
            } else {
                cursor_label.set_text("");
            }
        } else {
            cursor_label.set_text("");
        }
    }

    // Функция отрисовки графика - оптимизированная версия
    private void draw_graph(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // Очистка фона
        cr.set_source_rgb(1, 1, 1);
        cr.paint();
        
        // Увеличенные отступы для осей
        int margin_left = 80;    // Увеличен отступ слева для цифр и подписи
        int margin_right = 40;
        int margin_top = 40;
        int margin_bottom = 60;
        int graph_width = width - (margin_left + margin_right);
        int graph_height = height - (margin_top + margin_bottom);
        
        // Рисование осей
        cr.set_source_rgb(0, 0, 0);
        cr.set_line_width(1.0);
        
        // Ось X (время)
        cr.move_to(margin_left, height - margin_bottom);
        cr.line_to(width - margin_right, height - margin_bottom);
        // Стрелка оси X
        cr.move_to(width - margin_right, height - margin_bottom);
        cr.line_to(width - margin_right - 10, height - margin_bottom - 5);
        cr.move_to(width - margin_right, height - margin_bottom);
        cr.line_to(width - margin_right - 10, height - margin_bottom + 5);
        
        // Ось Y (угол)
        cr.move_to(margin_left, height - margin_bottom);
        cr.line_to(margin_left, margin_top);
        // Стрелка оси Y
        cr.move_to(margin_left, margin_top);
        cr.line_to(margin_left - 5, margin_top + 10);
        cr.move_to(margin_left, margin_top);
        cr.line_to(margin_left + 5, margin_top + 10);
        cr.stroke();
        
        // Подписи осей
        cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
        cr.set_font_size(12);
        
        // Подпись оси X
        cr.move_to(width - margin_right - 80, height - margin_bottom/2);
        cr.show_text("Время (сек)");
        
        // Подпись оси Y - увеличен отступ
        cr.save();
        cr.move_to(margin_left/4 - 10, height/2);  // Сдвинута влево
        cr.rotate(-Math.PI/2);
        cr.show_text("Угол (градусы)");
        cr.restore();
        
        // Градуировка оси X (до 30 секунд)
        for(int i = 0; i <= 30; i += 5) {  // Шаг 5 секунд
            int x = margin_left + (graph_width * i) / 30;
            cr.move_to(x, height - margin_bottom + 5);
            cr.line_to(x, height - margin_bottom - 5);
            string label = i.to_string();
            cr.move_to(x - 5, height - margin_bottom + 20);
            cr.show_text(label);
        }
        
        // Градуировка оси Y
        for(int i = -180; i <= 180; i += 45) {
            float y = height - margin_bottom - ((i + 180) * graph_height) / 360;
            cr.move_to(margin_left - 5, y);
            cr.line_to(margin_left + 5, y);
            string label = "%d°".printf(i);
            cr.move_to(margin_left - 45, y + 5);
            cr.show_text(label);
        }
        cr.stroke();
        
        if (angle_data.length == 0) return;
        
        // Рисуем график данных
        cr.set_source_rgb(0, 0, 1);
        
        // Начальная точка графика
        cr.move_to(margin_left, 
                 height - margin_bottom - ((angle_data[0] + 180) * graph_height) / 360);
        
        // Остальные точки графика
        for (int i = 1; i < angle_data.length; i++) {
            float angle = angle_data[i];
            float x = margin_left + (i * graph_width) / (MAX_MEASUREMENT_TIME * SAMPLE_RATE);
            if (x > width - margin_right) break;  // Остановка если вышли за границы
            float y = height - margin_bottom - ((angle + 180) * graph_height) / 360;
            cr.line_to(x, y);
        }
        cr.stroke();
        
        // Отображение курсора и значения под ним
        if (cursor_x >= margin_left && cursor_x <= width - margin_right && angle_data.length > 0) {
            // Вычисляем время в точке курсора (исправлено для корректного преобразования double в float)
            float time_fraction = (float)((cursor_x - margin_left) / graph_width);
            float time_seconds = time_fraction * MAX_MEASUREMENT_TIME;
            
            // Проверяем, не вышли ли за пределы измеренного времени
            int expected_points = (int)(time_seconds * SAMPLE_RATE); // 10 точек в секунду
            if (expected_points >= angle_data.length) {
                return; // Завершаем без перерисовки курсора
            }
            
            // Рисуем вертикальную линию курсора
            cr.set_source_rgb(1, 0, 0);
            cr.set_line_width(1.0);
            cr.move_to(cursor_x, margin_top);
            cr.line_to(cursor_x, height - margin_bottom);
            cr.stroke();
            
            // Метка уже обновляется через update_cursor_label()
        }
    }

    // Обработчик кнопки сохранения данных
    private void on_save_clicked() {
        var dialog = new Gtk.FileDialog();
        dialog.title = "Сохранить данные";
        dialog.initial_name = "measurement.csv";
        
        dialog.save.begin(window, null, (obj, res) => {
            try {
                var file = dialog.save.end(res);
                if (file != null) {
                    string path = file.get_path();
                    if (path != null) {
                        if (!path.has_suffix(".csv")) {
                            path = path + ".csv";
                        }
                        save_data_to_file(path);
                    }
                }
            } catch (GLib.IOError e) {
                // Обработка ошибок ввода/вывода
                print("Ошибка ввода/вывода при сохранении: %s\n", e.message);
            } catch (GLib.Error e) {
                // Обработка других ошибок GLib
                print("Ошибка при сохранении: %s\n", e.message);
            }
        });
    }

    // Обработчик кнопки загрузки данных
    private void on_load_clicked() {
        var dialog = new Gtk.FileDialog();
        dialog.title = "Загрузить данные";
        
        dialog.open.begin(window, null, (obj, res) => {
            try {
                var file = dialog.open.end(res);
                if (file != null) {
                    string path = file.get_path();
                    if (path != null) {
                        load_data_from_file(path);
                    }
                }
            } catch (GLib.IOError e) {
                // Обработка ошибок ввода/вывода
                print("Ошибка ввода/вывода при загрузке: %s\n", e.message);
            } catch (GLib.Error e) {
                // Обработка других ошибок GLib
                print("Ошибка при загрузке: %s\n", e.message);
            }
        });
    }

    // Сохранение данных в файл CSV - улучшенный формат
    private void save_data_to_file(string filename) {
        // Открываем файл для записи
        var file = FileStream.open(filename, "w");
        if (file == null) {
            print("Не удалось открыть файл для записи: %s\n", filename);
            return;
        }
        
        // Проверяем, есть ли данные для сохранения
        if (angle_data.length == 0) {
            print("Предупреждение: нет данных для сохранения\n");
            // Записываем пустые метаданные с нулевыми значениями max и min углов
            file.printf("# Максимальный угол: 0.00\n");
            file.printf("# Минимальный угол: 0.00\n");
            file.printf("# Время,Угол\n");
            return;
        }
        
        // Записываем метаданные с проверкой на бесконечность
        file.printf("# Максимальный угол: %.2f\n", is_float_infinite(max_angle) ? 0.0f : max_angle);
        file.printf("# Минимальный угол: %.2f\n", is_float_infinite(min_angle) ? 0.0f : min_angle);
        file.printf("# Время,Угол\n");
        
        // Записываем точки данных
        for (int i = 0; i < angle_data.length; i++) {
            float angle = angle_data[i];
            float time = i / (float)SAMPLE_RATE; // 10 точек в секунду
            file.printf("%.1f,%.2f\n", time, angle);
        }
        
        print("Данные успешно сохранены в файл: %s (%d точек)\n", filename, angle_data.length);
    }

    // Загрузка данных из файла CSV - полностью переработанная версия с исправлениями
    private void load_data_from_file(string filename) {
        // Проверка существования файла
        if (!FileUtils.test(filename, FileTest.EXISTS)) {
            print("Ошибка: файл не существует: %s\n", filename);
            return;
        }
        
        print("Загрузка данных из файла: %s\n", filename);
        
        // Читаем весь файл в массив строк для отладки и надежной обработки
        string content;
        try {
            FileUtils.get_contents(filename, out content);
        } catch (Error e) {
            print("Ошибка чтения файла: %s\n", e.message);
            return;
        }
        
        // Определяем формат - европейский или стандартный
        bool is_european_format = detect_european_csv_format(content);
        if (is_european_format) {
            print("Обнаружен европейский формат CSV (с запятыми в качестве десятичного разделителя)\n");
        } else {
            print("Обнаружен стандартный формат CSV\n");
        }
        
        // Разделяем содержимое на строки
        string[] lines = content.split("\n");
        print("Файл содержит %d строк\n", lines.length);
        
        // Останавливаем текущее измерение, если оно активно
        if (is_measuring) {
            is_measuring = false;
            
            // Находим и обновляем кнопку
            var button = find_button_with_label("Стоп");
            if (button != null) {
                button.label = "Пуск";
            }
        }
        
        // Очищаем текущие данные
        angle_data = {};
        max_angle = -float.INFINITY;
        min_angle = float.INFINITY;
        
        // Флаг для отслеживания когда пройдены все заголовки
        bool header_section = true;
        int data_count = 0;
        
        // Обрабатываем каждую строку файла
        foreach (string line in lines) {
            string trimmed_line = line.strip();
            
            // Пропускаем пустые строки
            if (trimmed_line == "") continue;
            
            // Обрабатываем метаданные и определяем конец заголовка
            if (trimmed_line.has_prefix("#")) {
                if (trimmed_line.has_prefix("# Максимальный угол:")) {
                    string max_str = trimmed_line.substring(19).strip();
                    double temp = 0.0;
                    if (double.try_parse(max_str, out temp)) {
                        print("Загружен максимальный угол из файла: %.2f\n", temp);
                        // Устанавливаем только если значение не равно 0
                        if (temp != 0) max_angle = (float)temp;
                    }
                } else if (trimmed_line.has_prefix("# Минимальный угол:")) {
                    string min_str = trimmed_line.substring(19).strip();
                    double temp = 0.0;
                    if (double.try_parse(min_str, out temp)) {
                        print("Загружен минимальный угол из файла: %.2f\n", temp);
                        // Устанавливаем только если значение не равно 0
                        if (temp != 0) min_angle = (float)temp;
                    }
                } else if (trimmed_line.has_prefix("# Время,Угол")) {
                    // Маркер конца заголовка
                    header_section = false;
                    print("Обнаружен конец заголовка\n");
                }
                continue; // Продолжаем пропускать строки заголовков
            }
            
            // Если строка не начинается с # и не пуста, это данные
            header_section = false;
            
            // Обработка строки с данными - теперь с поддержкой обоих форматов
            float time = 0.0f, angle = 0.0f;
            if (parse_csv_line(trimmed_line, out time, out angle)) {
                angle_data += angle;
                data_count++;
                
                // Вывод первых нескольких точек для отладки
                if (data_count <= 5) {
                    print("Загружена точка: время=%.1f, угол=%.2f\n", time, angle);
                }
                
                // Обновляем максимальное и минимальное значения угла
                if (angle > max_angle) max_angle = angle;
                if (angle < min_angle) min_angle = angle;
            }
        }
        
        print("Загружено %d точек данных\n", data_count);
        
        // Проверяем, есть ли загруженные данные
        if (angle_data.length == 0) {
            print("Внимание: из файла не загружено ни одной точки данных!\n");
            return;
        }
        
        // Если есть данные, обновляем интерфейс
        print("Максимальный угол: %.2f°, Минимальный угол: %.2f°\n", max_angle, min_angle);
        
        // Обновляем метки
        float last_angle = angle_data[angle_data.length - 1];
        angle_label.set_text("Угол в реальном времени: %.2f°".printf(last_angle));
        
        // Проверка на случай если max и min равны бесконечности (нет корректных данных)
        if (is_float_infinite(max_angle) || is_float_infinite(min_angle)) {
            if (angle_data.length > 0) {
                max_angle = angle_data[0];
                min_angle = angle_data[0];
                
                // Повторно проходим по данным для поиска min/max
                foreach (float angle in angle_data) {
                    if (angle > max_angle) max_angle = angle;
                    if (angle < min_angle) min_angle = angle;
                }
            }
        }
        
        max_angle_label.set_text("Максимальный угол: %.2f°, Минимальный угол: %.2f°".printf(
            max_angle, min_angle));
        
        // Принудительная перерисовка графика
        drawing_area.queue_draw();
        print("Данные успешно загружены и отображены\n");
    }

    // Ручной парсер для преобразования строки в число с плавающей точкой
    private bool manual_parse_float(string input_str, out float result) {
        result = 0.0f;
        
        // Создаем локальную копию строки вместо модификации входного параметра
        string str = input_str.strip();
        
        if (str == "")
            return false;
        
        // Определяем знак числа
        bool is_negative = str.has_prefix("-");
        if (is_negative) {
            // Создаем новую локальную строку без минуса вместо модификации входной строки
            str = str.substring(1); // Убираем минус
        }
        
        // Разделяем целую и дробную части
        string[] parts = str.split(".");
        if (parts.length > 2) // Если больше одной точки, это не валидное число
            return false;
        
        // Парсим целую часть
        int64 integer_part = 0;
        if (parts[0] != "") {
            // Проверяем, что целая часть состоит только из цифр
            foreach (char c in parts[0].to_utf8()) {
                if (!c.isdigit())
                    return false;
            }
            integer_part = int64.parse(parts[0]);
        }
        
        // Парсим дробную часть, если она есть
        double fractional_part = 0.0;
        if (parts.length == 2 && parts[1] != "") {
            // Проверяем, что дробная часть состоит только из цифр
            foreach (char c in parts[1].to_utf8()) {
                if (!c.isdigit())
                    return false;
            }
            
            double divisor = Math.pow(10, parts[1].length);
            fractional_part = int64.parse(parts[1]) / divisor;
        }
        
        // Собираем итоговое число
        double value = integer_part + fractional_part;
        if (is_negative)
            value = -value;
        
        result = (float)value;
        return true;
    }

    // Улучшенная функция для парсинга строки CSV с ручным парсером чисел
    private bool parse_csv_line(string line, out float time_value, out float angle_value) {
        // Инициализируем выходные параметры
        time_value = 0.0f;
        angle_value = 0.0f;
        
        if (line == null || line.strip() == "")
            return false;
            
        // Отладочный вывод для проблемных строк
        print("Парсинг CSV строки: '%s'\n", line);
        
        // Обработка европейского формата с запятыми вместо точек
        string[] parts = line.split(",");
        
        if (parts.length == 4) {
            // Европейский формат: 0,1,-38,71 -> время 0.1, значение -38.71
            
            // Проверяем, является ли третья часть просто знаком минус
            bool negative_angle = false;
            string part2 = parts[2].strip();
            string part3 = parts[3].strip();
            
            if (part2 == "-" && part3.length > 0) {
                // Особый случай, когда число выглядит так: "0,1,-,71"
                negative_angle = true;
                part2 = "0"; // Заменяем минус на 0 для дальнейшего парсинга
            } else if (part2.has_prefix("-") && part2.length > 1) {
                // Обычный случай с отрицательным числом: "0,1,-38,71"
                negative_angle = true;
                part2 = part2.substring(1); // Убираем знак минус
            }
            
            // Собираем время и угол в формате с точкой
            string time_str = parts[0].strip() + "." + parts[1].strip();
            string angle_str = (negative_angle ? "-" : "") + part2 + "." + part3;
            
            print("Преобразование: время '%s' → время_str '%s'\n", parts[0] + "," + parts[1], time_str);
            print("Преобразование: угол '%s' → угол_str '%s'\n", parts[2] + "," + parts[3], angle_str);
            
            // Используем ручной парсер вместо float.try_parse
            bool time_parsed = manual_parse_float(time_str, out time_value);
            bool angle_parsed = manual_parse_float(angle_str, out angle_value);
            
            if (time_parsed && angle_parsed) {
                print("✓ Успешно распознаны числа: время=%.1f, угол=%.2f\n", time_value, angle_value);
                return true;
            } else {
                print("✗ Ошибка парсинга: time_parsed=%s, angle_parsed=%s\n", 
                      time_parsed.to_string(), angle_parsed.to_string());
            }
        } else if (parts.length == 2) {
            // Стандартный формат: 0.1,38.71
            string time_str = parts[0].strip();
            string angle_str = parts[1].strip();
            
            // Используем ручной парсер вместо float.try_parse
            bool time_parsed = manual_parse_float(time_str, out time_value);
            bool angle_parsed = manual_parse_float(angle_str, out angle_value);
            
            if (time_parsed && angle_parsed) {
                print("✓ Успешно распознаны стандартные числа: время=%.1f, угол=%.2f\n", 
                      time_value, angle_value);
                return true;
            } else {
                print("✗ Не удалось преобразовать время '%s' или угол '%s' в числа\n", 
                      time_str, angle_str);
            }
        } else {
            print("Неверный формат строки CSV: ожидалось 2 или 4 колонки, получено %d\n", parts.length);
        }
        
        return false;
    }

    // Новый улучшенный метод для поиска кнопки по тексту
    private Gtk.Button? find_button_with_label(string target_label) {
        // Ищем среди всех дочерних виджетов главного окна
        return find_button_recursive(window, target_label);
    }

    // Рекурсивный поиск кнопки по всей иерархии виджетов
    private Gtk.Button? find_button_recursive(Gtk.Widget widget, string target_label) {
        if (widget is Gtk.Button) {
            var button = (Gtk.Button)widget;
            if (button.label == target_label) {
                return button;
            }
        }
        
        // Если у виджета есть дочерние элементы - проверяем их
        if (widget is Gtk.Box || widget is Gtk.Window || widget is Gtk.Frame) {
            // Перебираем дочерние виджеты для контейнеров
            var child = widget.get_first_child();
            while (child != null) {
                var result = find_button_recursive(child, target_label);
                if (result != null) {
                    return result;
                }
                child = child.get_next_sibling();
            }
        }
        
        return null;
    }

    // Отображение диалога ошибки аутентификации
    private void show_error_dialog() {
        var error_dialog = new Gtk.Window();
        error_dialog.title = "Ошибка";
        error_dialog.modal = true;
        error_dialog.default_width = 300;
        error_dialog.default_height = 100;
        
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
        box.margin_start = 24;
        box.margin_end = 24;
        box.margin_top = 24;
        box.margin_bottom = 24;
        
        var header = new Gtk.Label(null);
        header.set_markup("<span weight='bold' size='larger'>Ошибка аутентификации</span>");
        
        var label = new Gtk.Label("Неверный пароль. Попробуйте снова.");
        label.add_css_class("error-message");
        
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        button_box.halign = Gtk.Align.END;
        
        var ok_button = new Gtk.Button.with_label("OK");
        ok_button.add_css_class("suggested-action");
        
        box.append(header);
        box.append(label);
        button_box.append(ok_button);
        box.append(button_box);
        
        error_dialog.set_child(box);
        
        // Подключаем сигналы
        ok_button.clicked.connect(() => {
            error_dialog.destroy();
            show_password_dialog();
        });
        
        error_dialog.present();
    }

    // Обработчик активации поля ввода пароля
    private void password_entry_activate(Gtk.Widget entry) {
        var dialog = entry.get_ancestor(typeof(Gtk.Window)) as Gtk.Window;
        
        var password = ((Gtk.Editable)entry).get_text();
        if (password != null && password != "") {
            string command;
            
            try {
                string? current_exe = FileUtils.read_link("/proc/self/exe");
                
                if (current_exe != null) {
                    command = "echo '%s' | sudo -S \"%s\"".printf(
                        password, 
                        current_exe);
                    
                    dialog.destroy();
                    
                    // Запускаем команду с sudo
                    int status = Posix.system(command);
                    if (status == 0) {
                        if (main_loop != null) main_loop.quit();
                    } else {
                        show_error_dialog();
                    }
                }
            } catch (FileError e) {
                print("Ошибка при получении пути к исполняемому файлу: %s\n", e.message);
            }
        }
    }

    // Отображение диалога запроса пароля
    private void show_password_dialog() {
        var dialog = new Gtk.Window();
        dialog.title = "Аутентификация";
        dialog.modal = true;
        dialog.default_width = 400;
        dialog.default_height = 200;
        
        var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 24;
        content.margin_bottom = 24;
        
        // Заголовок
        var header = new Gtk.Label(null);
        header.set_markup("<span weight='bold' size='larger'>Требуются права администратора</span>");
        header.halign = Gtk.Align.START;
        
        // Описание
        var description = new Gtk.Label(
            "Для работы с устройством необходимы права администратора.\n" +
            "Пожалуйста, введите пароль."
        );
        description.justify = Gtk.Justification.LEFT;
        description.halign = Gtk.Align.START;
        description.wrap = true;
        description.add_css_class("dim-label");
        
        // Поле ввода пароля
        var entry = new Gtk.PasswordEntry();
        entry.show_peek_icon = true;
        entry.margin_top = 12;
        entry.margin_bottom = 12;
        
        // Кнопки
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        button_box.halign = Gtk.Align.END;
        
        var cancel_button = new Gtk.Button.with_label("Отмена");
        var ok_button = new Gtk.Button.with_label("Аутентификация");
        ok_button.add_css_class("suggested-action");
        
        button_box.append(cancel_button);
        button_box.append(ok_button);
        
        // Добавляем все элементы в контейнер
        content.append(header);
        content.append(description);
        content.append(entry);
        content.append(button_box);
        
        dialog.set_child(content);
        
        // CSS стили
        var provider = new Gtk.CssProvider();
        try {
            provider.load_from_string("""
                entry { margin: 6px 0; }
                .error-message { color: @error_color; }
                button { min-width: 120px; }
            """);
            
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } catch {
            // Упрощаем обработку исключений
            print("Ошибка загрузки CSS\n");
        }
        
        // Подключаем сигналы
        ok_button.clicked.connect(() => {
            password_entry_activate(entry);
        });
        cancel_button.clicked.connect(() => {
            dialog.destroy();
        });
        entry.activate.connect(() => {
            password_entry_activate(entry);
        });
        dialog.close_request.connect(() => {
            if (main_loop != null) main_loop.quit();
            return false;
        });
        
        dialog.present();
    }

    // Отображение диалога ошибки устройства
    private void show_device_error_dialog() {
        var error_dialog = new Gtk.Window();
        error_dialog.title = "Ошибка устройства";
        error_dialog.modal = true;
        error_dialog.default_width = 400;
        error_dialog.default_height = 200;
        
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
        box.margin_start = 24;
        box.margin_end = 24;
        box.margin_top = 24;
        box.margin_bottom = 24;
        
        var header = new Gtk.Label(null);
        header.set_markup("<span weight='bold' size='larger'>Устройство не найдено</span>");
        
        var label = new Gtk.Label("Проверьте подключение Arduino к компьютеру и перезапустите программу.");
        label.wrap = true;
        label.add_css_class("error-message");
        
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        button_box.halign = Gtk.Align.END;
        
        var ok_button = new Gtk.Button.with_label("OK");
        ok_button.add_css_class("suggested-action");
        
        box.append(header);
        box.append(label);
        button_box.append(ok_button);
        box.append(button_box);
        
        error_dialog.set_child(box);
        
        // Подключаем сигналы
        ok_button.clicked.connect(() => {
            error_dialog.destroy();
        });
        error_dialog.close_request.connect(() => {
            if (device_error_main_loop != null) device_error_main_loop.quit();
            return false;
        });
        
        error_dialog.present();
    }

    // После открытия порта добавляем настройку скорости обмена данными
    private bool setup_arduino_port() {
        if (serial_fd == -1) return false;
        
        print("Настройка Arduino...\n");
        
        // Небольшая задержка для установления соединения
        Thread.usleep(2000000); // 2 секунды
        
        // Очистка буфера
        Posix.tcflush(serial_fd, Posix.TCIOFLUSH);
        
        // Отправка команды для инициализации, если нужно
        var init_cmd = "i".data; // команда инициализации
        Posix.write(serial_fd, init_cmd, 1);
        
        print("Arduino настроено\n");
        return true;
    }

    // Добавляем метод для попытки открытия портов
    private bool try_open_ports() {
        string[] ports = {
            "/dev/ttyACM0",
            "/dev/ttyACM1",
            "/dev/ttyUSB0",
            "/dev/ttyUSB1",
            "/dev/arduino"
        };
        
        bool port_opened = false;
        foreach (string port in ports) {
            print("Пробуем открыть порт: %s\n", port);
            serial_fd = open_serial_port(port);
            if (serial_fd != -1) {
                print("Успешно открыт порт %s без прав администратора\n", port);
                port_opened = true;
                // Настраиваем Arduino после успешного открытия порта
                setup_arduino_port();
                break;
            }
        }
        
        return port_opened;
    }

    // Главная точка входа в программу - полностью переработан
    public static int main(string[] args) {
        Gtk.init();
        
        var app = new MaitnikApp();
        
        // Сначала пытаемся открыть порт без прав администратора
        bool port_opened = app.try_open_ports();
        
        // Если не удалось открыть порт и у нас нет прав root, пробуем получить права
        if (!port_opened && Posix.geteuid() != 0) {
            print("Не удалось открыть порт без прав администратора, запрашиваем пароль...\n");
            main_loop = new MainLoop(null, false);
            app.show_password_dialog();
            main_loop.run();
            return 0; // Программа будет перезапущена с правами sudo
        }
        
        // Если получили права администратора, но все еще нужно открыть порт
        if (!port_opened && Posix.geteuid() == 0) {
            print("Запуск с правами администратора, повторно пытаемся открыть порты\n");
            port_opened = app.try_open_ports();
        }

        // Если и с правами администратора не удалось открыть порт
        if (!port_opened) {
            device_error_main_loop = new MainLoop(null, false);
            app.show_device_error_dialog();
            device_error_main_loop.run();
            return 1;
        }

        // Запускаем приложение
        int status = app.run(args);
        
        // Закрываем порт при выходе
        if (app.serial_fd != -1) {
            Posix.close(app.serial_fd);
        }

        return status;
    }

    // Применяем CSS стили (обновлено для совместимости с GTK 4.12+)
    private void apply_css_styles() {
        var provider = new Gtk.CssProvider();
        string css_data = """
            .stats-label { font-size: 14px; padding: 8px; }
            .header-section { margin-bottom: 24px; }
            .stats-section { margin-top: 24px; background: alpha(#000, 0.03); border-radius: 6px; padding: 12px; }
            .view { margin: 12px 0; }
            button { min-width: 120px; }
        """;
        
        try {
            provider.load_from_string(css_data);
            
            // Примечание: это предупреждение мы не можем устранить в текущей версии GTK
            // Метод add_provider_for_display остается единственным способом применить CSS
            // до тех пор, пока GTK не предоставит альтернативное API.
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } catch (Error e) {
            // Обработка ошибок от load_from_string
            print("Ошибка загрузки CSS: %s\n", e.message);
        }
    }

    // Вспомогательная функция для проверки, является ли число бесконечным
    private bool is_float_infinite(float value) {
        // Проверка на -∞ и +∞
        return (value == float.INFINITY || value == -float.INFINITY);
    }

    // Функция обнаружения формата CSV файла - добавим перед load_data_from_file
    private bool detect_european_csv_format(string content) {
        string[] lines = content.split("\n");
        foreach (string line in lines) {
            string trimmed = line.strip();
            if (trimmed == "" || trimmed.has_prefix("#")) continue;
            
            // Ищем строки вида: "0,1,-38,71"
            string[] parts = trimmed.split(",");
            if (parts.length == 4) {
                // Проверим, что части выглядят как числа
                double n1, n2, n3, n4;
                if (double.try_parse(parts[0], out n1) && 
                    double.try_parse(parts[1], out n2) && 
                    double.try_parse(parts[2], out n3) && 
                    double.try_parse(parts[3], out n4)) {
                    return true;
                }
            }
        }
        return false;
    }
}
