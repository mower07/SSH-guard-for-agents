[🇺🇸 English](README.md) | 🇷🇺 Русский

# SSH Guard — мониторинг и защита серверов через Telegram

Набор bash-скриптов для VPS/выделенных серверов под управлением Ubuntu/Debian.
Уведомляет в Telegram о каждом SSH-входе, умно батчит сообщения, блокирует неизвестные IP автоматически.

---

## Кому поможет

- Разработчикам и системным администраторам с VPS
- Командам где несколько серверов, агентов, рабочих мест или сотрудников
- Тем, кто хочет знать о подозрительных входах в реальном времени — без логов и мониторинга вручную

---

## Что внутри

### Умные уведомления о SSH-входах
- **Известный IP** → входы копятся в очередь, раз в минуту одно сообщение:
  ```
  🔐 3 SSH-входов на MyServer | myserver (1.2.3.4)
  10:00:01 — 10:00:48
    • Admin (1.2.3.4) — root — 10:00:01
    • RemoteAgent (5.6.7.8) — root — 10:00:32
  ```
- **Неизвестный IP, первый раз** → мгновенный алерт + вопрос ДА/НЕТ + 5 мин таймаут
- **Неизвестный IP, повторный вход** → **немедленный автобан** без ожидания
- **Нет ответа 5 минут** → IP автоматически блокируется через UFW

### Мониторинг сервисов
Каждые 5 минут проверяет что сервисы живые. Если упал — пишет в Telegram.

### Мониторинг диска и памяти
Алерт при заполнении диска >80% или памяти >90%.

### Проверка аномальных портов
Раз в сутки сравнивает открытые порты с эталоном. Если появился новый порт — алерт.

### Масштабируемость
Единый белый список IP для всех серверов. Добавить новый сервер — одна команда.

---

## Требования

- Ubuntu/Debian с UFW
- Telegram-бот (создать через @BotFather, получить токен)
- SSH-доступ к серверу с ключом (без пароля)
- Один из серверов — **мастер** (хранит общий whitelist и синхронизирует остальные)

---

## Быстрый старт

### 1. Создать Telegram-бота
- Написать @BotFather → `/newbot`
- Сохранить токен
- Узнать свой Telegram ID: написать @userinfobot

### 2. Заполнить `.env_secrets`
```bash
cp scripts/.env_secrets.template /root/.env_secrets
nano /root/.env_secrets
chmod 600 /root/.env_secrets
```

### 3. Развернуть на мастер-сервере
```bash
mkdir -p /root/scripts/security/pending
cp scripts/*.sh /root/scripts/security/
cp scripts/*.conf /root/scripts/security/
chmod 700 /root/scripts/security/*.sh

# SSH-алерт через PAM
echo 'session optional pam_exec.so /root/scripts/security/ssh-alert.sh' >> /etc/pam.d/sshd

# Cron
(crontab -l 2>/dev/null; \
  echo "*/5 * * * * /root/scripts/security/monitor.sh"; \
  echo "0 8 * * * /root/scripts/security/port-check.sh"; \
  echo "* * * * * /root/scripts/security/pending-check.sh"; \
  echo "* * * * * /root/scripts/security/send-queue.sh"; \
  echo "0 3 * * * /root/scripts/security/sync-whitelist.sh") | crontab -
```

### 4. Добавить свой IP в белый список
```bash
echo "1.2.3.4 Admin" >> /root/scripts/security/whitelist-ips.conf
```

### 5. Разрешить UFW без пароля (если запускаете от non-root)
```bash
echo "myuser ALL=(ALL) NOPASSWD: /usr/sbin/ufw" >> /etc/sudoers.d/myuser-ufw
chmod 440 /etc/sudoers.d/myuser-ufw
```

### 6. Добавить следующий сервер
```bash
./onboard-server.sh root@IP "Метка"
```

---

## Логика блокировки неизвестных IP

```
Неизвестный IP подключился
        │
        ▼
Первый раз? ──Да──▶ Алерт + создать pending файл
        │                  │
        │            Ожидание ответа
        │           ДА ◀──┤──▶ НЕТ / 5 мин тишина
        │            │              │
        │     Добавить в         Заблокировать
        │     whitelist          ufw deny from IP
        │
       Нет (pending уже есть)
        │
        ▼
   Немедленный бан 🚫
```

---

## Работа с несколькими серверами и агентами

### Архитектура

```
Мастер-сервер (хранит whitelist)
├── /root/scripts/security/whitelist-ips.conf  ← единый список
├── /root/scripts/security/servers.conf        ← список серверов
└── cron: sync-whitelist.sh раз в сутки → пушит на все серверы

Сервер-2, Сервер-3, ..., Сервер-N
└── /root/scripts/security/whitelist-ips.conf  ← получают от мастера
```

### Добавить новый сервер (с мастера)
```bash
./onboard-server.sh root@NEW_IP "Prod-Backend"
```

### Несколько рабочих мест одного человека
```bash
echo "1.2.3.4 Admin-home" >> /root/scripts/security/whitelist-ips.conf
echo "5.6.7.8 Admin-office" >> /root/scripts/security/whitelist-ips.conf
echo "9.10.11.12 Admin-mobile" >> /root/scripts/security/whitelist-ips.conf
```

### Несколько сотрудников
```bash
echo "1.2.3.4 Ivan" >> whitelist-ips.conf
echo "5.6.7.8 Maria-home" >> whitelist-ips.conf
echo "13.14.15.16 Alexey" >> whitelist-ips.conf
```

### 10 агентов / ботов
```bash
echo "10.0.0.1 Agent-1" >> whitelist-ips.conf
echo "10.0.0.2 Agent-2" >> whitelist-ips.conf
# после добавления — синхронизировать:
bash /root/scripts/security/sync-whitelist.sh
```

---

## Настройка скриптов

`ssh-alert.sh` — метка сервера в уведомлениях:
```bash
SERVER_LABEL="MyServer"
```

`monitor.sh` — список сервисов для мониторинга:
```bash
SERVICES="nginx postgresql myapp"
```

---

## Частые проблемы

### Меня заблокировало — не могу зайти по SSH
1. Зайти через KVM/VNC консоль хостинг-провайдера
2. Выполнить: `ufw delete deny from ТВОЙ_IP`
3. Добавить IP в whitelist: `echo "1.2.3.4 Admin" >> /root/scripts/security/whitelist-ips.conf`

### Один и тот же IP спрашивает дважды
PAM иногда открывает два сеанса. Проверить дубли:
```bash
grep "ssh-alert" /etc/pam.d/sshd
# Если две строки — удалить дубль:
sed -i '0,/ssh-alert/! {/ssh-alert/d}' /etc/pam.d/sshd
```

### Whitelist обновил, но сервер всё равно спрашивает
Синхронизировать вручную:
```bash
bash /root/scripts/security/sync-whitelist.sh
```

### Агент/бот постоянно триггерит алерты
Добавить статический IP агента в whitelist. Если IP динамический — зафиксировать через статический IP сервера агента.

### Сервер заблокировал нужный IP
```bash
ufw delete deny from IP_АДРЕС
echo "IP_АДРЕС Метка" >> /root/scripts/security/whitelist-ips.conf
bash /root/scripts/security/sync-whitelist.sh
```

---

## Структура файлов

```
scripts/
├── ssh-alert.sh          # PAM-хук: алерт + очередь + автобан
├── send-queue.sh         # Батчинг: объединяет входы в одно сообщение
├── pending-check.sh      # Автоблокировка по таймауту (5 мин)
├── monitor.sh            # Мониторинг сервисов + диск + память
├── port-check.sh         # Аномальные порты (раз в сутки)
├── sync-whitelist.sh     # Синхронизация whitelist на все серверы
├── onboard-server.sh     # Деплой на новый сервер одной командой
├── whitelist-ips.conf    # Белый список IP
├── servers.conf          # Список серверов для синхронизации
└── .env_secrets.template # Шаблон токенов (не коммитить!)
```

---

## Известные ограничения

- UFW-блокировка блокирует весь трафик с IP, не только SSH
- Ответ "ДА" обрабатывается вручную — добавить IP в whitelist самостоятельно
- `monitor.sh` — список сервисов прописывается отдельно на каждом сервере
- Динамические IP (мобильный, некоторые провайдеры) придётся обновлять вручную
- Один Telegram-бот уведомляет одного человека; для команды — доработать скрипт под несколько chat_id

---

Сделано в феврале 2026. Работает на Ubuntu 22.04 / 24.04.

## Самовосстановление OpenClaw (systemd watchdog + timer)

В репозиторий добавлен лёгкий профиль самовосстановления сервисов OpenClaw.

Файлы:
- `scripts/service-healthcheck.sh`
- `systemd/openclaw-healthcheck.service`
- `systemd/openclaw-healthcheck.timer`

Установка (user-level systemd):
```bash
mkdir -p ~/.config/systemd/user
cp systemd/openclaw-healthcheck.service ~/.config/systemd/user/
cp systemd/openclaw-healthcheck.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now openclaw-healthcheck.timer
```

Что делает:
- каждые 90 сек проверяет `openclaw-gateway.service`, `telegram-mcp.service`, `telegram-dm.service`
- если сервис не active - перезапускает
- anti-spam лог событий (`~/.cache/openclaw-healthcheck/events.log`)
- без LLM-вызовов, нагрузка минимальная
