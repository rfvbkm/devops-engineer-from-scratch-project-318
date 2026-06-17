### Hexlet tests and linter status:
[![Actions Status](https://github.com/rfvbkm/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/rfvbkm/devops-engineer-from-scratch-project-318/actions)

## Развёрнутый сервер

DNS-имя: `hexlet.mooo.com`

- Приложение: http://hexlet.mooo.com/
- API: http://hexlet.mooo.com/api/bulletins
- Swagger UI: http://hexlet.mooo.com/swagger-ui/index.html

## Yandex Object Storage (ручная настройка)

### 1. Создание бакета

1. Откройте [консоль Yandex Cloud](https://console.cloud.yandex.ru/) и выберите каталог (folder), в котором будет жить хранилище.
2. Перейдите в **Object Storage** → **Бакеты** → **Создать бакет**.
3. Задайте имя бакета — оно должно быть **глобально уникальным** в Object Storage (латиница в нижнем регистре, цифры, дефис; 3–63 символа). Пример: `hexlet-bulletins-prod`.
4. **Класс хранилища**: Standard.
5. **Доступ к списку объектов**: ограниченный (бакет приватный). Приложение отдаёт ссылки через presigned URL, публичный доступ не нужен.
6. Остальные параметры оставьте по умолчанию и нажмите **Создать бакет**.

Через CLI (опционально):

```bash
yc storage bucket create --name hexlet-bulletins-prod --default-storage-class standard
```

### 2. Сервисный аккаунт

Приложению нужен отдельный сервисный аккаунт с правами на запись и чтение объектов в бакете.

1. **IAM** → **Сервисные аккаунты** → **Создать сервисный аккаунт**.
2. Имя, например: `bulletin-storage`.
3. Назначьте роль на уровне каталога: **`storage.editor`** — достаточно для загрузки и чтения объектов во всех бакетах каталога. Если нужен доступ только к одному бакету, вместо роли на каталог можно выдать права через ACL бакета (шаг ниже).
4. Сохраните сервисный аккаунт.

Через CLI:

```bash
yc iam service-account create --name bulletin-storage

yc resource-manager folder add-access-binding <FOLDER_ID> \
  --role storage.editor \
  --subject serviceAccount:<SERVICE_ACCOUNT_ID>
```

**ACL бакета (альтернатива роли на каталог):** откройте бакет → **Безопасность** → **ACL** → добавьте сервисный аккаунт с правами **READ** и **WRITE**.

### 3. Статический ключ доступа

1. Откройте созданный сервисный аккаунт → вкладка **Ключи доступа** → **Создать ключ доступа** → **Статический ключ доступа**.
2. Описание — произвольное (например, `bulletin-app`).
3. После создания сохраните **идентификатор ключа** (Access Key ID) и **секретный ключ** (Secret Access Key). Секрет показывается **один раз**; восстановить его нельзя — при потере создайте новый ключ.

Через CLI:

```bash
yc iam access-key create --service-account-name bulletin-storage
```

В выводе будут поля `key_id` и `secret`.

### 4. Переменные окружения

Подставьте полученные значения в переменные из таблицы выше (или в `group_vars/servers/vault.yml` для Ansible):

| Переменная | Значение для Yandex Cloud |
|------------|---------------------------|
| `STORAGE_S3_BUCKET` | имя бакета, например `hexlet-bulletins-prod` |
| `STORAGE_S3_REGION` | `ru-central1` |
| `STORAGE_S3_ENDPOINT` | `https://storage.yandexcloud.net` |
| `STORAGE_S3_ACCESSKEY` | идентификатор статического ключа |
| `STORAGE_S3_SECRETKEY` | секретный ключ |
| `STORAGE_S3_CDNURL` | необязательно; префикс публичного CDN, если настроен |

Пример для локального запуска:

```bash
export STORAGE_S3_BUCKET=hexlet-bulletins-prod
export STORAGE_S3_REGION=ru-central1
export STORAGE_S3_ENDPOINT=https://storage.yandexcloud.net
export STORAGE_S3_ACCESSKEY=YCAJ...
export STORAGE_S3_SECRETKEY=YCP...
```

Для Ansible скопируйте `group_vars/servers/vault.yml.example` в `vault.yml`, заполните поля `vault_storage_s3_*` и зашифруйте: `ansible-vault encrypt group_vars/servers/vault.yml`.

### 5. Проверка доступа

С установленным [AWS CLI](https://aws.amazon.com/cli/) и настроенным endpoint:

```bash
aws --endpoint-url=https://storage.yandexcloud.net \
  s3 ls s3://hexlet-bulletins-prod/ \
  --region ru-central1
```

После деплоя приложения загрузите изображение через UI и убедитесь, что объект появился в бакете (префикс `bulletins/`).

## Требования для деплоя

Ansible-плейбуки запускаются с **хост-машины** и настраивают **целевой сервер** из группы `servers` в `inventory.ini`.

### Хост-машина

Машина, с которой выполняются `make provision` и `make deploy`:

- **Ansible** 2.14+ и **Make**.
- **Python 3** и **pip** (для модулей Ansible и коллекции `community.docker`).
- **SSH-клиент** и приватный ключ с доступом к целевому серверу (логин без пароля или через `ssh-agent`).
- Клон репозитория с настроенным `inventory.ini` (хост, пользователь, группа `servers`).
- Зашифрованный `group_vars/servers/vault.yml` (создаётся из `vault.yml.example`) и пароль Vault локально — в файле `.vault_pass` или при интерактивном запросе.
- Исходящий доступ в интернет для `ansible-galaxy collection install` (см. `requirements.yml`).

Первый запуск установит коллекции Ansible автоматически:

```bash
make ansible-collections   # community.general, community.docker
make provision             # первичная настройка сервера (один раз)
make monitoring            # развёртывание Prometheus на monitoring-ВМ
make deploy                # деплой/обновление контейнера приложения
```

### Целевая машина (сервер)

Сервер из `inventory.ini`, куда деплоится приложение. Плейбуки рассчитаны на **Debian/Ubuntu** (используется `apt`):

- **SSH** на порту 22, пользователь с правами **sudo** (Ansible работает с `become: true`).
- **Python 3** на сервере (`ansible_python_interpreter=/usr/bin/python3` в `inventory.ini`).
- Свободные входящие порты **80** и **443** (HTTP/HTTPS для nginx и Let's Encrypt). Порт **22** — для администрирования.
- **DNS A-запись** домена (`nginx_server_name` в `group_vars/servers/main.yml`) должна указывать на IP сервера до выпуска TLS-сертификата.
- Исходящий доступ в интернет: установка пакетов (`apt`), Docker Engine, certbot, pull образа из GHCR.

Плейбук `playbook.yml` устанавливает на сервер Docker, nginx, certbot и настраивает UFW. Роль `app` запускает контейнер приложения; внешние зависимости профиля `prod` задаются через vault:

- **PostgreSQL** — внешняя БД (например, Supabase); параметры подключения в `vault_spring_datasource_*`.
- **Yandex Object Storage** — S3-хранилище для изображений; параметры в `vault_storage_s3_*` (см. раздел выше).
- **GHCR** — приватный registry; при необходимости логин/пароль в `vault_docker_registry_*`.

## Мониторинг и метрики

На сервере собираются метрики хоста (Node Exporter) и приложения (Spring Boot Actuator / Prometheus).

### Endpoints и порты

| Компонент | Порт | Путь | Доступ |
|-----------|------|------|--------|
| Приложение (HTTP) | `8080` | `/` | Публично через Nginx (`80`/`443`) |
| Spring Boot Actuator (management) | `9090` | `/actuator/health`, `/actuator/prometheus` | Локально на хосте; снаружи — через Nginx с basic auth |
| Node Exporter | `9100` | `/metrics` | Порт `9100` (UFW), scrape Prometheus |
| Nginx reverse proxy | `80`/`443` | `/actuator/health`, `/actuator/prometheus` | Basic auth (`metrics` + пароль из `vault.yml`) |

Параметры задаются в `group_vars/servers/main.yml` и `inventory.ini`:

- `app_port` — основной HTTP-порт приложения (по умолчанию `8080`)
- `app_management_port` — management-порт Actuator (по умолчанию `9090`)
- `node_exporter_port` — порт Node Exporter (по умолчанию `9100`)
- `nginx_management_basic_auth_user` — пользователь basic auth для `/actuator/*` (по умолчанию `metrics`)
- `vault_nginx_management_basic_auth_password` — пароль basic auth (в `group_vars/servers/vault.yml`)

Nginx проксирует healthcheck и метрики с management-порта и пишет JSON-логи:

- access: `/var/log/nginx/management.access.json` (формат `json_access`)
- HTTP-ошибки 4xx/5xx: `/var/log/nginx/management.error.json` (формат `json_error`)
- внутренние ошибки Nginx: `/var/log/nginx/management.internal.error.log`

### Обязательные метрики хоста (Node Exporter)

| Категория | Метрика | Описание |
|-----------|---------|----------|
| CPU load | `node_load1` | Средняя загрузка CPU за 1 минуту |
| CPU load | `node_load5` | Средняя загрузка CPU за 5 минут |
| CPU load | `node_load15` | Средняя загрузка CPU за 15 минут |
| CPU load | `node_cpu_seconds_total` | Время CPU по режимам (user/system/idle/…) |
| Память | `node_memory_MemTotal_bytes` | Общий объём RAM |
| Память | `node_memory_MemAvailable_bytes` | Доступная RAM |
| Память | `node_memory_SwapTotal_bytes` | Объём swap |
| Диски | `node_filesystem_avail_bytes` | Свободное место на ФС |
| Диски | `node_filesystem_size_bytes` | Размер ФС |
| Диски | `node_disk_read_bytes_total` | Прочитано с диска |
| Диски | `node_disk_written_bytes_total` | Записано на диск |
| Сеть | `node_network_receive_bytes_total` | Входящий трафик по интерфейсам |
| Сеть | `node_network_transmit_bytes_total` | Исходящий трафик по интерфейсам |
| Процессы | `node_procs_running` | Число запущенных процессов |
| Процессы | `node_procs_blocked` | Число заблокированных процессов |
| Системные сервисы | `node_systemd_unit_state` | Состояние systemd-юнитов (collector `systemd`) |

### Обязательные метрики приложения (Actuator / Prometheus)

| Категория | Метрика | Описание |
|-----------|---------|----------|
| Uptime | `process_uptime_seconds` | Время работы JVM-процесса |
| Uptime | `application_ready_time_seconds` | Время до готовности приложения |
| HTTP | `http_server_requests_seconds_count` | Счётчик HTTP-запросов |
| HTTP | `http_server_requests_seconds_sum` | Суммарное время обработки запросов |
| HTTP | `http_server_requests_seconds_max` | Максимальное время обработки |
| JVM | `jvm_memory_used_bytes` | Использование памяти JVM |
| JVM | `jvm_gc_pause_seconds_count` | Количество пауз GC |
| JVM | `jvm_threads_live` | Число live-потоков |
| Диск приложения | `disk_free_bytes` | Свободное место в контейнере |
| Диск приложения | `disk_total_bytes` | Общий объём в контейнере |

### Проверка curl


**Management-порт напрямую (без Nginx):**

```bash
# Health (агрегированный)
curl -sS http://<app-host>:9090/actuator/health

# Readiness / liveness
curl -sS http://<app-host>:9090/actuator/health/readiness
curl -sS http://<app-host>:9090/actuator/health/liveness

# Prometheus-метрики приложения
curl -sS http://<app-host>:9090/actuator/prometheus
```

**Через Nginx (с basic auth):**

```bash
curl -sS -u metrics:'<password>' https://<app-host>/actuator/health
curl -sS -u metrics:'<password>' https://<app-host>/actuator/prometheus
```

**Node Exporter (после `make provision`):**

```bash
curl -sS http://<app-host>:9100/metrics
```

## Prometheus

Отдельная ВМ группы `monitoring` собирает метрики с сервера приложения. Развёртывание и повторный деплой — одной командой:

```bash
make monitoring
```

Плейбук `monitoring.yml` устанавливает Docker, настраивает UFW (только SSH и сервисы наблюдаемости) и запускает контейнер Prometheus в сети `monitoring` с отдельными volume'ами:

| Volume на хосте | Назначение |
|-----------------|------------|
| `/opt/prometheus/config` | `prometheus.yml` (шаблон из Ansible vars) |
| `/opt/prometheus/config/rules` | правила алертинга (`roles/prometheus/files/alerts.yml`) |
| `/opt/prometheus/data` | TSDB (метрики) |

Конфигурация и alert rules лежат в репозитории; чувствительные данные — в `group_vars/monitoring/vault.yml` (см. `vault.yml.example`).

### Адрес Prometheus

- **UI (графики):** http://176.53.174.159:9090/graph
- **Таргеты:** http://176.53.174.159:9090/targets
- **Health:** http://176.53.174.159:9090/-/healthy

Сервер мониторинга: `176.53.174.159` (группа `monitoring`, хост `prometheus` в `inventory.ini`).

### Таргеты scrape

Список задаётся в `group_vars/monitoring/main.yml` (`prometheus_scrape_jobs`) и подставляется в шаблон `roles/prometheus/templates/prometheus.yml.j2`:

| Job | Таргет | Источник vars |
|-----|--------|---------------|
| `prometheus` | `localhost:9090` | self-monitoring |
| `node_exporter` | `<app-host>:9100` | `prometheus_app_host`, `prometheus_node_exporter_port` |
| `spring_boot_actuator` | `<app-host>:9090/actuator/prometheus` | `prometheus_app_host`, `prometheus_app_management_port` |

Порты management (`9090`) на сервере приложения открыты в UFW **только** для IP monitoring-ВМ (см. `playbook.yml`).

Зарезервированы места для `nginx_exporter` и `loki` в `prometheus_scrape_jobs`.

### Проверка `up == 1`

После `make monitoring` и `make provision` на сервере приложения все таргеты должны быть в состоянии **UP**:

1. Откройте http://176.53.174.159:9090/targets — в колонке **State** у каждого job должно быть `UP`.
2. В PromQL (http://176.53.174.159:9090/graph) выполните запрос:

```promql
up
```

Ожидаемый результат — значение `1` для каждого таргета (`job="node_exporter"`, `job="spring_boot_actuator"`, `job="prometheus"`).

```bash
# Проверка через API
curl -sS 'http://176.53.174.159:9090/api/v1/query?query=up' | jq '.data.result[] | {job: .metric.job, instance: .metric.instance, value: .value[1]}'
```

### ВМ мониторинга в Yandex Cloud

1. Создайте ВМ Ubuntu в том же каталоге, что и сервер приложения (2 vCPU, 2 GB RAM достаточно).
2. В **группах безопасности** / **firewall** разрешите входящий трафик только на порты **22** (SSH) и **9090** (Prometheus). Исходящий — для scrape таргетов на сервере приложения.
3. Добавьте SSH-ключ пользователя `user` (как на сервере приложения).
4. Укажите IP в `inventory.ini` в группе `[monitoring]`.
5. Запустите `make monitoring`.

### Требования для monitoring-ВМ

- **SSH** на порту 22, пользователь с sudo.
- **Python 3**, исходящий доступ в интернет (Docker, pull образа `prom/prometheus`).
- Входящие порты: **22**, **9090** (UFW настраивается плейбуком).
- Ansible-коллекция `community.docker` (устанавливается через `make ansible-collections`).

