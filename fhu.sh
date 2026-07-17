# 1. Создаем папку для GitHub Actions
mkdir -p .github/workflows
mkdir -p src

# 2. Создаем файл воркфлоу для автоматической сборки
cat << 'EOF' > .github/workflows/build.yml
name: PlatformIO Mega Build V2 (With Keyboard)
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repo
        uses: actions/checkout@v3

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install PlatformIO
        run: |
          python -m pip install --upgrade pip
          pip install --upgrade platformio

      - name: Build Firmware
        run: pio run
EOF

# 3. Создаем улучшенный platformio.ini с поддержкой русских шрифтов
cat << 'EOF' > platformio.ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200

lib_deps =
    bodmer/TFT_eSPI@^2.5.31
    lvgl/lvgl@^8.3.9
    Links2004/arduinoVNC@^1.5
    adafruit/Adafruit GFX Library@^1.11.9
    adafruit/Adafruit ILI9341@^1.6.0
    adafruit/Adafruit ST7735 and ST7789 Library@^1.10.3
    https://github.com/PaulStoffregen/XPT2046_Touchscreen.git

build_flags =
    -D USER_SETUP_LOADED=1
    -D ILI9341_2_DRIVER=1
    -D TFT_MISO=12
    -D TFT_MOSI=13
    -D TFT_SCLK=14
    -D TFT_CS=15
    -D TFT_DC=2
    -D TFT_RST=-1
    -D TFT_BL=21
    -D LOAD_GLCD=1
    -D LOAD_FONT2=1
    -D LOAD_FONT4=1
    -D SPI_FREQUENCY=55000000
    -D SPI_TOUCH_FREQUENCY=2500000
    -D LV_CONF_SKIP=1
    -D LV_TICK_CUSTOM=1
    -D LV_COLOR_DEPTH=16
    ; --- Включаем кириллицу и шрифты для Русского Языка ---
    -D LV_TXT_ENC=LV_TXT_ENC_UTF8
    -D LV_FONT_MONTSERRAT_14=1
    -D LV_FONT_DEFAULT=\&lv_font_montserrat_14
EOF

# 4. Создаем МЕГА огромный main.cpp (Теперь тут ОЧЕНЬ много строк!)
cat << 'EOF' > src/main.cpp
#include <Arduino.h>
#include <WiFi.h>
#include <TFT_eSPI.h>
#include <lvgl.h>
#include <VNC.h>
#include <XPT2046_Touchscreen.h>
#include <SPI.h>

// ==========================================
//           НАСТРОЙКИ ЖЕЛЕЗА ESP32
// ==========================================
TFT_eSPI tft = TFT_eSPI();

#define XPT2046_IRQ 36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK 25
#define XPT2046_CS 33
#define TFT_BL 21

SPIClass touchSPI(HSPI);
XPT2046_Touchscreen ts(XPT2046_CS, XPT2046_IRQ);

// ==========================================
//         ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ VNC
// ==========================================
bool vnc_active = false;
bool vnc_paused = false;
bool vnc_kb_active = false;
int vnc_offset_x = 0;
int vnc_offset_y = 0;

// ==========================================
//          ЭЛЕМЕНТЫ ИНТЕРФЕЙСА LVGL
// ==========================================
static lv_disp_draw_buf_t draw_buf;
static lv_color_t buf[320 * 20]; 

lv_obj_t * main_ui_screen;
lv_obj_t * pause_menu_screen;
lv_obj_t * kb_overlay_screen;
lv_obj_t * vnc_custom_kb;

lv_obj_t * ip_ta;
lv_obj_t * port_ta;
lv_obj_t * sys_kb;
lv_obj_t * wifi_dd;
lv_obj_t * pwd_ta;
lv_obj_t * wifi_stat_lbl;
lv_obj_t * sys_info_lbl;
lv_obj_t * offset_x_lbl;
lv_obj_t * offset_y_lbl;

// ==========================================
//   МЕГА-МАССИВЫ ДЛЯ РУССКОЙ КЛАВИАТУРЫ
// ==========================================
// Для русской раскладки нам нужны свои карты кнопок. 
static const char * kb_map_ru_lc[] = {
    "й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ", LV_SYMBOL_BACKSPACE, "\n",
    "ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", LV_SYMBOL_NEW_LINE, "\n",
    "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", ".", ",", "\n",
    "EN", "1#", LV_SYMBOL_CLOSE, " ", LV_SYMBOL_LEFT, LV_SYMBOL_RIGHT, ""
};

static const lv_btnmatrix_ctrl_t kb_ctrl_ru_lc[] = {
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 6, 2, 2
};

static const char * kb_map_en_lc[] = {
    "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", LV_SYMBOL_BACKSPACE, "\n",
    "a", "s", "d", "f", "g", "h", "j", "k", "l", LV_SYMBOL_NEW_LINE, "\n",
    "z", "x", "c", "v", "b", "n", "m", ".", ",", "\n",
    "RU", "1#", LV_SYMBOL_CLOSE, " ", LV_SYMBOL_LEFT, LV_SYMBOL_RIGHT, ""
};

static const lv_btnmatrix_ctrl_t kb_ctrl_en_lc[] = {
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 6, 2, 2
};

// ==========================================
//    ДРАЙВЕР VNC И КОНВЕРТЕР KEYSYM
// ==========================================

// Конвертация символа (UTF-8 или ASCII) в X11 Keysym для отправки на ПК
uint32_t char_to_keysym(const char * txt) {
    if (strlen(txt) == 1) {
        char c = txt[0];
        if (c >= 'a' && c <= 'z') return c;
        if (c >= 'A' && c <= 'Z') return c;
        if (c >= '0' && c <= '9') return c;
        if (c == ' ') return 0x0020;
        if (c == '.') return 0x002e;
        if (c == ',') return 0x002c;
    }
    
    // Специальные кнопки LVGL
    if (strcmp(txt, LV_SYMBOL_BACKSPACE) == 0) return 0xFF08; // Backspace
    if (strcmp(txt, LV_SYMBOL_NEW_LINE) == 0) return 0xFF0D;  // Enter
    if (strcmp(txt, LV_SYMBOL_LEFT) == 0) return 0xFF51;      // Arrow Left
    if (strcmp(txt, LV_SYMBOL_RIGHT) == 0) return 0xFF53;     // Arrow Right
    
    // Русские буквы (X11 Cyrillic Keysyms)
    if (strcmp(txt, "й") == 0) return 0x06CA;
    if (strcmp(txt, "ц") == 0) return 0x06C3;
    if (strcmp(txt, "у") == 0) return 0x06D5;
    if (strcmp(txt, "к") == 0) return 0x06CB;
    if (strcmp(txt, "е") == 0) return 0x06C5;
    if (strcmp(txt, "н") == 0) return 0x06CE;
    if (strcmp(txt, "г") == 0) return 0x06C7;
    if (strcmp(txt, "ш") == 0) return 0x06DB;
    if (strcmp(txt, "щ") == 0) return 0x06DD;
    if (strcmp(txt, "з") == 0) return 0x06DA;
    if (strcmp(txt, "х") == 0) return 0x06C8;
    if (strcmp(txt, "ъ") == 0) return 0x06DF;
    if (strcmp(txt, "ф") == 0) return 0x06C6;
    if (strcmp(txt, "ы") == 0) return 0x06D9;
    if (strcmp(txt, "в") == 0) return 0x06D7;
    if (strcmp(txt, "а") == 0) return 0x06C1;
    if (strcmp(txt, "п") == 0) return 0x06D0;
    if (strcmp(txt, "р") == 0) return 0x06D2;
    if (strcmp(txt, "о") == 0) return 0x06CF;
    if (strcmp(txt, "л") == 0) return 0x06CC;
    if (strcmp(txt, "д") == 0) return 0x06C4;
    if (strcmp(txt, "ж") == 0) return 0x06D6;
    if (strcmp(txt, "э") == 0) return 0x06DC;
    if (strcmp(txt, "я") == 0) return 0x06D1;
    if (strcmp(txt, "ч") == 0) return 0x06DE;
    if (strcmp(txt, "с") == 0) return 0x06D3;
    if (strcmp(txt, "м") == 0) return 0x06CD;
    if (strcmp(txt, "и") == 0) return 0x06C9;
    if (strcmp(txt, "т") == 0) return 0x06D4;
    if (strcmp(txt, "ь") == 0) return 0x06D8;
    if (strcmp(txt, "б") == 0) return 0x06C2;
    if (strcmp(txt, "ю") == 0) return 0x06C0;

    return 0;
}

class MyVNCDisplay : public VNCdisplay {
public:
    bool hasCopyRect(void) { return false; }
    uint32_t getHeight(void) { return tft.height(); }
    uint32_t getWidth(void) { return tft.width(); }
    
    void draw_area(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint8_t *data) {
        if (!vnc_active || vnc_paused || vnc_kb_active) return; 
        int draw_x = x - vnc_offset_x;
        int draw_y = y - vnc_offset_y;
        if(draw_x >= tft.width() || draw_y >= tft.height() || draw_x + w < 0 || draw_y + h < 0) return;
        tft.pushImage(draw_x, draw_y, w, h, (uint16_t*)data);
    }
    void draw_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint16_t color) {
        if (!vnc_active || vnc_paused || vnc_kb_active) return;
        tft.fillRect(x - vnc_offset_x, y - vnc_offset_y, w, h, color);
    }
    void copy_rect(uint32_t src_x, uint32_t src_y, uint32_t dest_x, uint32_t dest_y, uint32_t w, uint32_t h) {}
    void area_update_start(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
        if (!vnc_active || vnc_paused || vnc_kb_active) return;
        tft.setAddrWindow(x - vnc_offset_x, y - vnc_offset_y, w, h);
        tft.startWrite();
    }
    void area_update_data(char *data, uint32_t pixel) {
        if (!vnc_active || vnc_paused || vnc_kb_active) return;
        tft.pushColors((uint16_t*)data, pixel, true);
    }
    void area_update_end(void) {
        if (!vnc_active || vnc_paused || vnc_kb_active) return;
        tft.endWrite();
    }
};

MyVNCDisplay vnc_disp;
arduinoVNC vnc(&vnc_disp);

// ==========================================
//      ДРАЙВЕРЫ ЭКРАНА И ТАЧСКРИНА LVGL
// ==========================================
void my_disp_flush(lv_disp_drv_t *disp_drv, const lv_area_t *area, lv_color_t *color_p) {
    uint32_t w = (area->x2 - area->x1 + 1);
    uint32_t h = (area->y2 - area->y1 + 1);
    tft.startWrite();
    tft.setAddrWindow(area->x1, area->y1, w, h);
    tft.pushColors((uint16_t *)&color_p->full, w * h, true);
    tft.endWrite();
    lv_disp_flush_ready(disp_drv);
}

void my_touchpad_read(lv_indev_drv_t * indev_drv, lv_indev_data_t * data) {
    if(ts.touched()) {
        TS_Point p = ts.getPoint();
        data->state = LV_INDEV_STATE_PR;
        
        uint16_t x, y;
        int rot = tft.getRotation();
        
        switch(rot) {
            case 0: x = map(p.x, 300, 3900, 0, 240); y = map(p.y, 300, 3900, 0, 320); break;
            case 1: x = map(p.x, 300, 3900, 0, 320); y = map(p.y, 300, 3900, 0, 240); break;
            case 2: x = map(p.x, 3900, 300, 0, 240); y = map(p.y, 3900, 300, 0, 320); break;
            case 3: x = map(p.x, 3900, 300, 0, 320); y = map(p.y, 3900, 300, 0, 240); break;
            default: x = map(p.x, 300, 3900, 0, 320); y = map(p.y, 300, 3900, 0, 240); break;
        }
        
        data->point.x = x;
        data->point.y = y;

        // ПЛАВАЮЩИЕ КНОПКИ VNC (Только если VNC активен и мы не в меню/клаве)
        if(vnc_active && !vnc_paused && !vnc_kb_active) {
            // Кнопка "=" (Меню) - Правый нижний угол (40x40)
            if(x > tft.width() - 40 && y > tft.height() - 40) {
                vnc_paused = true;
                lv_scr_load(pause_menu_screen); 
                return;
            }
            // Кнопка "K" (Клава) - Левее от меню (40x40)
            if(x > tft.width() - 85 && x < tft.width() - 45 && y > tft.height() - 40) {
                vnc_kb_active = true;
                lv_scr_load(kb_overlay_screen); // Врубаем клаву
                return;
            }
            // Если не попали по кнопкам - отправляем клик в комп
            vnc.mouseEvent(x + vnc_offset_x, y + vnc_offset_y, 1); 
        }

    } else {
        data->state = LV_INDEV_STATE_REL;
        if(vnc_active && !vnc_paused && !vnc_kb_active) vnc.mouseEvent(0, 0, 0); 
    }
}

// ==========================================
//          ЛОГИКА ВИРТУАЛЬНОЙ КЛАВЫ
// ==========================================
static void vnc_kb_event_cb(lv_event_t * e) {
    lv_obj_t * obj = lv_event_get_target(e);
    uint16_t btn_id = lv_btnmatrix_get_selected_btn(obj);
    if(btn_id == LV_BTNMATRIX_BTN_NONE) return;

    const char * txt = lv_btnmatrix_get_btn_text(obj, btn_id);
    if(txt == NULL) return;

    // Переключение языков
    if(strcmp(txt, "RU") == 0) {
        lv_keyboard_set_map(vnc_custom_kb, LV_KEYBOARD_MODE_USER_1, kb_map_ru_lc, kb_ctrl_ru_lc);
        return;
    }
    if(strcmp(txt, "EN") == 0) {
        lv_keyboard_set_map(vnc_custom_kb, LV_KEYBOARD_MODE_USER_1, kb_map_en_lc, kb_ctrl_en_lc);
        return;
    }
    // Закрытие клавы
    if(strcmp(txt, LV_SYMBOL_CLOSE) == 0) {
        vnc_kb_active = false;
        tft.fillScreen(TFT_BLACK);
        lv_scr_load(lv_obj_create(NULL)); // Прячем LVGL, возвращаем VNC
        return;
    }

    // Если это кнопка символа - отправляем её по VNC!
    uint32_t keysym = char_to_keysym(txt);
    if(keysym != 0) {
        vnc.keyEvent(keysym, 0b1); // Нажали
        delay(10);
        vnc.keyEvent(keysym, 0b0); // Отпустили
    }
}

// ==========================================
//     ЛОГИКА ИНТЕРФЕЙСА (ОБЩАЯ ЧАСТЬ)
// ==========================================
static void ta_event_cb(lv_event_t * e) {
    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t * ta = lv_event_get_target(e);
    if(code == LV_EVENT_FOCUSED) {
        lv_keyboard_set_textarea(sys_kb, ta);
        lv_obj_clear_flag(sys_kb, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(sys_kb); 
    }
    if(code == LV_EVENT_DEFOCUSED) {
        lv_keyboard_set_textarea(sys_kb, NULL);
        lv_obj_add_flag(sys_kb, LV_OBJ_FLAG_HIDDEN);
    }
}

static void btn_vnc_conn_cb(lv_event_t * e) {
    if(WiFi.status() != WL_CONNECTED) return;
    const char * ip = lv_textarea_get_text(ip_ta);
    const char * port = lv_textarea_get_text(port_ta);
    
    tft.fillScreen(TFT_BLACK);
    tft.setTextColor(TFT_WHITE);
    tft.setCursor(10, 10);
    tft.println("Connecting to VNC...");
    
    vnc.begin(ip, atoi(port)); 
    vnc_active = true;
    vnc_paused = false;
    vnc_kb_active = false;
    lv_scr_load(lv_obj_create(NULL)); 
}

static void btn_wifi_scan_cb(lv_event_t * e) {
    lv_label_set_text(wifi_stat_lbl, "Scanning...");
    lv_timer_handler();
    int n = WiFi.scanNetworks();
    if (n == 0) {
        lv_dropdown_set_options(wifi_dd, "No networks");
    } else {
        String options = "";
        for (int i = 0; i < n; ++i) {
            options += WiFi.SSID(i);
            if (i < n - 1) options += "\n";
        }
        lv_dropdown_set_options(wifi_dd, options.c_str());
        lv_label_set_text(wifi_stat_lbl, "Scan complete!");
    }
}

static void btn_wifi_conn_cb(lv_event_t * e) {
    char ssid[64];
    lv_dropdown_get_selected_str(wifi_dd, ssid, sizeof(ssid));
    const char * pwd = lv_textarea_get_text(pwd_ta);
    WiFi.begin(ssid, pwd);
    lv_label_set_text(wifi_stat_lbl, "Connecting...");
}

static void slider_bright_cb(lv_event_t * e) {
    lv_obj_t * slider = lv_event_get_target(e);
    int val = lv_slider_get_value(slider);
    ledcWrite(0, val); 
}

static void btn_orient_event_cb(lv_event_t * e) {
    lv_obj_t * btn = lv_event_get_target(e);
    lv_obj_t * label = lv_obj_get_child(btn, 0);
    const char * txt = lv_label_get_text(label);
    
    int rot = 1; 
    if(strcmp(txt, "Rot 0") == 0) rot = 0;
    if(strcmp(txt, "Rot 1") == 0) rot = 1;
    if(strcmp(txt, "Rot 2") == 0) rot = 2;
    if(strcmp(txt, "Rot 3") == 0) rot = 3;
    
    tft.setRotation(rot);
    
    lv_disp_drv_t * disp_drv = lv_disp_get_default()->driver;
    disp_drv->hor_res = tft.width();
    disp_drv->ver_res = tft.height();
    lv_disp_drv_update(lv_disp_get_default(), disp_drv);
}

// Меню Паузы
static void btn_vnc_resume_cb(lv_event_t * e) {
    vnc_paused = false;
    tft.fillScreen(TFT_BLACK);
    lv_scr_load(lv_obj_create(NULL)); 
}

static void btn_vnc_disconnect_cb(lv_event_t * e) {
    vnc_active = false;
    vnc_paused = false;
    tft.fillScreen(TFT_BLACK);
    lv_scr_load(main_ui_screen);
}

static void slider_offset_cb(lv_event_t * e) {
    lv_obj_t * slider = lv_event_get_target(e);
    uint32_t id = (uintptr_t)lv_event_get_user_data(e);
    int val = lv_slider_get_value(slider);
    
    if (id == 0) { 
        vnc_offset_x = val;
        char buf[32]; snprintf(buf, sizeof(buf), "X Offset: %d", val);
        lv_label_set_text(offset_x_lbl, buf);
    } else {       
        vnc_offset_y = val;
        char buf[32]; snprintf(buf, sizeof(buf), "Y Offset: %d", val);
        lv_label_set_text(offset_y_lbl, buf);
    }
}

// ==========================================
//          СБОРКА ЭКРАНОВ
// ==========================================
void build_main_ui() {
    main_ui_screen = lv_obj_create(NULL);
    
    lv_obj_t * tv = lv_tabview_create(main_ui_screen, LV_DIR_TOP, 40);
    lv_obj_t * t1 = lv_tabview_add_tab(tv, "VNC");
    lv_obj_t * t2 = lv_tabview_add_tab(tv, "Wi-Fi");
    lv_obj_t * t3 = lv_tabview_add_tab(tv, "Set");
    lv_obj_t * t4 = lv_tabview_add_tab(tv, "Info");

    ip_ta = lv_textarea_create(t1); lv_textarea_set_placeholder_text(ip_ta, "IP: 192.168..."); lv_obj_set_width(ip_ta, 160); lv_obj_align(ip_ta, LV_ALIGN_TOP_LEFT, 0, 0); lv_obj_add_event_cb(ip_ta, ta_event_cb, LV_EVENT_ALL, NULL);
    port_ta = lv_textarea_create(t1); lv_textarea_set_text(port_ta, "5900"); lv_obj_set_width(port_ta, 80); lv_obj_align(port_ta, LV_ALIGN_TOP_RIGHT, 0, 0); lv_obj_add_event_cb(port_ta, ta_event_cb, LV_EVENT_ALL, NULL);

    lv_obj_t * btn_conn = lv_btn_create(t1); lv_obj_set_size(btn_conn, 140, 50); lv_obj_align(btn_conn, LV_ALIGN_CENTER, 0, 0); lv_obj_add_event_cb(btn_conn, btn_vnc_conn_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t * lbl_conn = lv_label_create(btn_conn); lv_label_set_text(lbl_conn, "START VNC");

    wifi_dd = lv_dropdown_create(t2); lv_dropdown_set_options(wifi_dd, "Press Scan..."); lv_obj_set_width(wifi_dd, 180); lv_obj_align(wifi_dd, LV_ALIGN_TOP_LEFT, 0, 0);
    lv_obj_t * btn_scan = lv_btn_create(t2); lv_obj_set_width(btn_scan, 70); lv_obj_align(btn_scan, LV_ALIGN_TOP_RIGHT, 0, 0); lv_obj_add_event_cb(btn_scan, btn_wifi_scan_cb, LV_EVENT_CLICKED, NULL); lv_obj_t * lbl_scan = lv_label_create(btn_scan); lv_label_set_text(lbl_scan, "Scan");
    pwd_ta = lv_textarea_create(t2); lv_textarea_set_placeholder_text(pwd_ta, "Password"); lv_obj_set_width(pwd_ta, 180); lv_obj_align(pwd_ta, LV_ALIGN_TOP_LEFT, 0, 45); lv_obj_add_event_cb(pwd_ta, ta_event_cb, LV_EVENT_ALL, NULL);
    lv_obj_t * btn_wconn = lv_btn_create(t2); lv_obj_set_width(btn_wconn, 70); lv_obj_align(btn_wconn, LV_ALIGN_TOP_RIGHT, 0, 45); lv_obj_add_event_cb(btn_wconn, btn_wifi_conn_cb, LV_EVENT_CLICKED, NULL); lv_obj_t * lbl_wconn = lv_label_create(btn_wconn); lv_label_set_text(lbl_wconn, "Join");
    wifi_stat_lbl = lv_label_create(t2); lv_label_set_text(wifi_stat_lbl, "Status: Disconnected"); lv_obj_align(wifi_stat_lbl, LV_ALIGN_TOP_MID, 0, 95);

    lv_obj_t * br_lbl = lv_label_create(t3); lv_label_set_text(br_lbl, "Screen Brightness:"); lv_obj_align(br_lbl, LV_ALIGN_TOP_LEFT, 0, 0);
    lv_obj_t * br_slider = lv_slider_create(t3); lv_slider_set_range(br_slider, 10, 255); lv_slider_set_value(br_slider, 200, LV_ANIM_OFF); lv_obj_set_width(br_slider, 250); lv_obj_align(br_slider, LV_ALIGN_TOP_MID, 0, 20); lv_obj_add_event_cb(br_slider, slider_bright_cb, LV_EVENT_VALUE_CHANGED, NULL);
    const char* rot_btns[] = {"Rot 0", "Rot 1", "Rot 2", "Rot 3"};
    for(int i=0; i<4; i++) {
        lv_obj_t * b = lv_btn_create(t3); lv_obj_set_size(b, 65, 35); int rx = (i%2) * 80; int ry = (i/2) * 45; lv_obj_align(b, LV_ALIGN_TOP_LEFT, rx + 10, ry + 60); lv_obj_add_event_cb(b, btn_orient_event_cb, LV_EVENT_CLICKED, NULL); lv_obj_t * l = lv_label_create(b); lv_label_set_text(l, rot_btns[i]);
    }
    
    sys_info_lbl = lv_label_create(t4); lv_label_set_text(sys_info_lbl, "Booting..."); lv_obj_align(sys_info_lbl, LV_ALIGN_TOP_LEFT, 0, 0);

    sys_kb = lv_keyboard_create(main_ui_screen); lv_obj_add_flag(sys_kb, LV_OBJ_FLAG_HIDDEN);
}

void build_pause_menu() {
    pause_menu_screen = lv_obj_create(NULL);
    lv_obj_t * title = lv_label_create(pause_menu_screen); lv_label_set_text(title, "VNC PAUSED"); lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 10);
    lv_obj_t * btn_res = lv_btn_create(pause_menu_screen); lv_obj_set_size(btn_res, 120, 40); lv_obj_align(btn_res, LV_ALIGN_TOP_LEFT, 10, 40); lv_obj_add_event_cb(btn_res, btn_vnc_resume_cb, LV_EVENT_CLICKED, NULL); lv_obj_t * l_res = lv_label_create(btn_res); lv_label_set_text(l_res, "RESUME");
    lv_obj_t * btn_disc = lv_btn_create(pause_menu_screen); lv_obj_set_size(btn_disc, 120, 40); lv_obj_align(btn_disc, LV_ALIGN_TOP_RIGHT, -10, 40); lv_obj_add_event_cb(btn_disc, btn_vnc_disconnect_cb, LV_EVENT_CLICKED, NULL); lv_obj_t * l_disc = lv_label_create(btn_disc); lv_label_set_text(l_disc, "DISCONNECT"); lv_obj_set_style_bg_color(btn_disc, lv_palette_main(LV_PALETTE_RED), 0);
    
    offset_x_lbl = lv_label_create(pause_menu_screen); lv_label_set_text(offset_x_lbl, "X Offset: 0"); lv_obj_align(offset_x_lbl, LV_ALIGN_CENTER, 0, -5);
    lv_obj_t * s_off_x = lv_slider_create(pause_menu_screen); lv_slider_set_range(s_off_x, 0, 1920); lv_slider_set_value(s_off_x, 0, LV_ANIM_OFF
