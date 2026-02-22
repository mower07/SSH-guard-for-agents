# SSH Guard — мониторинг и защита серверов через Telegram

Набор bash-скриптов для VPS/выделенных серверов под управлением Ubuntu/Debian.
Уведомляет в Telegram о каждом SSH-входе, блокирует неизвестные IP автоматически.

---

## Кому поможет

- Разработчикам и системным администраторам с VPS
- Командам где несколько серверов, агентов, рабочих мест или сотрудников
- Тем, кто хочет знать о подозрительных входах в реальном времени — без логов и мониторинга вручную

---

## Что внутри

### Уведомления о SSH-входах
- Известный IP → обычный алерт с меткой: `🔐 SSH вход на Server-1 | myserver (95.X.X.X) — Admin (1.2.3.4)`
- Неизвестный IP → вопрос в Telegram: "Это ты? ДА/НЕТ"
- Нет ответа 5 минут → IP автоматически блокируется через UFW + алерт о блокировке

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
- Один из серверов — **мастер** (хранит общий whitelist и раздаёт его остальным)

---

## Быстрый старт

### 1. Создать Telegram-бота
- Написать @BotFather → `/newbot`
- Сохранить токен
- Узнать свой Telegram ID: написать @userinfobot

### 2. Заполнить `.env_secrets` на мастер-сервере
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
  echo "*/5 * * * * /root/scripts/security/sync-whitelist.sh") | crontab -
```

### 4. Добавить свой IP в белый список
```bash
echo "1.2.3.4 Admin" >> /root/scripts/security/whitelist-ips.conf
```

### 5. Добавить следующий сервер
```bash
./onboard-server.sh root@IP "Метка"
# Пример:
./onboard-server.sh root@95.X.X.X "Server-2"
```

---

## Настройка `ssh-alert.sh`

В начале скрипта поменять метку сервера:
```bash
SERVER_LABEL="MyServer"
```

В `monitor.sh` — список сервисов для мониторинга:
```bash
SERVICES="nginx postgresql myapp"
```

---

## Работа с несколькими серверами и агентами

### Архитектура

```
Мастер-сервер (хранит whitelist)
├── /root/scripts/security/whitelist-ips.conf  ← единый список
├── /root/scripts/security/servers.conf        ← список серверов
└── cron: sync-whitelist.sh каждые 5 мин → пушит на все серверы

Сервер-2, Сервер-3, ..., Сервер-N
└── /root/scripts/security/whitelist-ips.conf  ← получают от мастера
```

### Добавить новый сервер (с мастера)
```bash
./onboard-server.sh root@NEW_IP "Prod-Backend"
```
Скрипт автоматически:
- Создаёт директории и pending/
- Копирует `.env_secrets` и `whitelist-ips.conf`
- Устанавливает PAM-хук
- Добавляет cron для `pending-check.sh`
- Вносит сервер в `servers.conf`

### Несколько рабочих мест одного человека

Добавить все IP в whitelist с разными метками:
```bash
echo "1.2.3.4 Admin-home" >> /root/scripts/security/whitelist-ips.conf
echo "5.6.7.8 Admin-office" >> /root/scripts/security/whitelist-ips.conf
echo "9.10.11.12 Admin-mobile" >> /root/scripts/security/whitelist-ips.conf
```

> ⚠️ Мобильный интернет и некоторые провайдеры дают динамические IP.
> Такие адреса менять придётся вручную при смене.

### Несколько сотрудников

```bash
echo "1.2.3.4 Иван" >> whitelist-ips.conf
echo "5.6.7.8 Мария-home" >> whitelist-ips.conf
echo "9.10.11.12 Мария-office" >> whitelist-ips.conf
echo "13.14.15.16 Алексей" >> whitelist-ips.conf
```

Каждый вход в лог-алерте будет подписан именем — сразу видно кто зашёл и откуда.

### 10 агентов на разных серверах

Каждый агент — это процесс (бот, AI-агент, скрипт), который подключается к серверам по SSH.
У каждого агента свой IP сервера, откуда он работает. Добавить в whitelist:

```bash
echo "10.0.0.1 Agent-1" >> whitelist-ips.conf
echo "10.0.0.2 Agent-2" >> whitelist-ips.conf
# ...
echo "10.0.0.10 Agent-10" >> whitelist-ips.conf
```

После обновления whitelist-а — синхронизировать вручную (или подождать 5 мин):
```bash
bash /root/scripts/security/sync-whitelist.sh
```

---

## Частые проблемы

### Меня заблокировало — не могу зайти по SSH

**Причина:** pending файл для твоего IP не был удалён вовремя, cron заблокировал.

**Решение:**
1. Зайти через KVM/VNC консоль хостинг-провайдера (без SSH)
2. Выполнить:
```bash
ufw delete deny from ТВОЙ_IP
```

**Профилактика:**
- Добавить свой IP в whitelist до первого входа
- Дать агенту право `sudo ufw` без пароля — тогда он сможет разблокировать сам:
```bash
echo "myuser ALL=(ALL) NOPASSWD: /usr/sbin/ufw" >> /etc/sudoers.d/myuser-ufw
chmod 440 /etc/sudoers.d/myuser-ufw
```

### Один и тот же IP спрашивает дважды

**Причина:** PAM открывает два сеанса на один SSH-вход (нормальное поведение).

**Решение:** Проверить что строка в `/etc/pam.d/sshd` ровно одна:
```bash
grep "ssh-alert" /etc/pam.d/sshd
```
Если две — удалить дубль:
```bash
sed -i '0,/ssh-alert/! {/ssh-alert/d}' /etc/pam.d/sshd
```

### Whitelist обновил, но сервер всё равно спрашивает

**Причина:** Синхронизация раз в 5 мин — ещё не успела.

**Решение:** Синхронизировать вручную:
```bash
bash /root/scripts/security/sync-whitelist.sh
```

### Агент/бот постоянно триггерит алерты

**Причина:** IP агента не в whitelist или IP сервера агента меняется (динамический).

**Решение:**
1. Добавить статический IP агента в whitelist
2. Или перевести агента на SSH-ключ с фиксированного сервера с известным IP

### Сервер заблокировал нужный IP автоматически

**Причина:** Никто не ответил на алерт в течение 5 минут.

**Решение:**
```bash
# Разблокировать вручную
ufw delete deny from IP_АДРЕС
# Добавить в whitelist чтобы не повторилось
echo "IP_АДРЕС Метка" >> /root/scripts/security/whitelist-ips.conf
bash /root/scripts/security/sync-whitelist.sh
```

---

## Как работает белый список

Файл `whitelist-ips.conf`:
```
1.2.3.4 Admin
5.6.7.8 RemoteAgent
9.10.11.12 Colleague
```

При входе скрипт ищет IP в списке:
- Нашёл → `Откуда: Admin (1.2.3.4)` без вопросов
- Не нашёл → спрашивает подтверждение, создаёт `.pending` файл

Ответ "ДА" → добавить IP вручную в `whitelist-ips.conf` + синхронизировать.
Ответ "НЕТ" или молчание 5 мин → `ufw insert 1 deny from IP`.

---

## Структура файлов

```
scripts/
├── ssh-alert.sh          # PAM-хук: алерт при SSH-входе
├── pending-check.sh      # Автоблокировка по таймауту (5 мин)
├── monitor.sh            # Мониторинг сервисов + диск + память
├── port-check.sh         # Аномальные порты
├── sync-whitelist.sh     # Синхронизация whitelist на все серверы
├── onboard-server.sh     # Деплой на новый сервер
├── whitelist-ips.conf    # Белый список IP
├── servers.conf          # Список серверов для синхронизации
└── .env_secrets.template # Шаблон токенов (не коммитить реальный файл!)
```

---

## Известные ограничения

- Блокировка через UFW блокирует весь трафик с IP, не только SSH
- Ответ "ДА" обрабатывается вручную — нужно самому добавить IP в whitelist
- `monitor.sh` — список сервисов прописывается отдельно на каждом сервере
- Динамические IP (мобильный, некоторые провайдеры) — придётся обновлять вручную
- Один Telegram-бот уведомляет одного человека. Для команды нужно доработать скрипт под рассылку нескольким chat_id

---

Сделано в феврале 2026. Работает на Ubuntu 22.04 / 24.04.
