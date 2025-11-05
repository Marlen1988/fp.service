#!/bin/bash

# ==========================================
#  Интерактивный установщик 'foreground' сервиса
# ==========================================

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Функции ---
print_info() {
    echo -e "\n${BLUE}INFO:${NC} $1"
}
print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}
print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}
print_warning() {
    echo -e "${YELLOW}WARN:${NC} $1"
}

# === 1. ПРОВЕРКА НА ROOT ===

print_info "Запуск установщика 'foreground' сервиса..."
if [ "$EUID" -ne 0 ]; then
  print_error "Этот скрипт необходимо запускать с правами root."
  echo "Пожалуйста, запустите: sudo ./install_fg_service.sh"
  exit 1
fi

# === 2. ИНТЕРАКТИВНЫЙ ВВОД ===

print_info "Пожалуйста, ответьте на несколько вопросов."
echo "Вы можете нажать Enter, чтобы использовать значения по умолчанию (в скобках)."

# -e позволяет использовать автодополнение, -i задает значение по умолчанию
read -e -i "fp.service" -p "  1. Введите имя для .service файла: " SERVICE_NAME
read -e -i "zhalgas" -p "  2. Введите имя пользователя (User): " SERVICE_USER
read -e -i "sudo" -p "  3. Введите имя группы (Group): " SERVICE_GROUP
read -e -i "/DATASET/project/scada/faceplate" -p "  4. Введите полный путь к папке Faceplate: " FACEPLATE_PATH

# Убираем / в конце, если он есть
FACEPLATE_PATH=${FACEPLATE_PATH%/}

# === 3. ВАЛИДАЦИЯ ===

print_info "Проверка введенных данных..."

# Проверяем, что бинарник существует
EXEC_FILE="$FACEPLATE_PATH/bin/faceplate"

if [ ! -f "$EXEC_FILE" ]; then
    print_error "Бинарник НЕ НАЙДЕН по пути: $EXEC_FILE"
    echo "Пожалуйста, проверьте путь и попробуйте снова."
    exit 1
else
    print_success "Бинарник найден: $EXEC_FILE"
fi

# Проверяем пользователя и группу
if ! id "$SERVICE_USER" &>/dev/null; then
    print_error "Пользователь '$SERVICE_USER' не существует в системе."
    exit 1
fi
if ! getent group "$SERVICE_GROUP" &>/dev/null; then
    print_error "Группа '$SERVICE_GROUP' не существует в системе."
    exit 1
fi

print_success "Пользователь и группа существуют."

# === 4. ГЕНЕРАЦИЯ ФАЙЛА ===

# Путь назначения
SERVICE_DEST_FILE="/etc/systemd/system/$SERVICE_NAME"

print_info "Подготовка unit-файла..."

# Генерируем содержимое .service файла в переменную
# 'cat <<EOF' - это "Here Document", он позволяет вставить многострочный текст
# Важно: $SERVICE_USER, $SERVICE_GROUP, $FACEPLATE_PATH и $EXEC_FILE будут заменены
SERVICE_CONTENT=$(cat <<EOF
[Unit]
Description=Faceplate SCADA Application Service (Foreground)
After=network.target

[Service]
# !! Процесс запускается в foreground
Type=simple

User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$FACEPLATE_PATH

# !! Запускаем бинарник напрямую
ExecStart=$EXEC_FILE foreground

Restart=always
RestartSec=5
LimitNOFILE=200000

[Install]
WantedBy=multi-user.target
EOF
)

# === 5. ПОДТВЕРЖДЕНИЕ ===

echo -e "\n${YELLOW}--- ПРОВЕРЬТЕ ДАННЫЕ ---${NC}"
echo "Сервис будет установлен сюда: ${GREEN}$SERVICE_DEST_FILE${NC}"
echo "Содержимое файла:"
echo -e "${BLUE}---------------------------------${NC}"
echo "$SERVICE_CONTENT"
echo -e "${BLUE}---------------------------------${NC}"
echo ""
read -p "Все верно? (y/n): " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Установка отменена."
    exit 0
fi

# === 6. УСТАНОВКА ===

print_info "Остановка старого сервиса (если он был)..."
systemctl stop "$SERVICE_NAME" &>/dev/null

print_info "1. Запись файла в $SERVICE_DEST_FILE..."
# 'echo -e' нужен, чтобы кавычки и переносы строк сохранились
echo -e "$SERVICE_CONTENT" > "$SERVICE_DEST_FILE"

print_info "2. Перезагрузка демонов systemd (daemon-reload)..."
systemctl daemon-reload

print_info "3. Включение автозагрузки сервиса (enable)..."
systemctl enable "$SERVICE_NAME"

print_info "4. Запуск сервиса $SERVICE_NAME (start)..."
systemctl start "$SERVICE_NAME"

# === 7. ФИНАЛ ===

print_success "Установка и запуск завершены!"
echo "Проверка статуса сервиса (через 2 секунды):"

sleep 2
systemctl status "$SERVICE_NAME"

exit 0
