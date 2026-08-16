# StillHere

Приватный self-hosted мессенджер для своих: чат и аудиозвонки 1:1, авторизация только по `@username` + паролю. Клиенты — Android и Windows (Flutter, один кодбейс). Бэкенд — Node.js/TypeScript, поднимается на любом вашем сервере одной командой.

Любой желающий может развернуть свой собственный **узел** (сервер) и пригласить туда друзей — данные остаются только на этом узле, никакого центрального сервиса StillHere нет. MIT license — код можно свободно форкать и менять.

## Как это работает

1. Вы разворачиваете узел на своём Linux-сервере одной командой (см. ниже) и задаёте **пароль узла**.
2. Друзья открывают приложение StillHere, на экране подключения вводят адрес вашего узла и этот пароль — так их устройство "спаривается" с узлом и получает долгоживущий токен доступа.
3. После этого каждый сам регистрирует personal-аккаунт по `@тегу` и своему собственному паролю — уже на этом узле. Тег и пароль профиля отдельные от пароля узла.
4. Дальше — обычный мессенджер: чат и звонки между пользователями одного узла.

Пароль узла не даёт доступ ни к чьей переписке сам по себе — это просто фильтр "свой/чужой" на уровне сервера, чтобы случайный человек, узнавший IP, не мог даже увидеть форму регистрации.

---

## Установка узла (one-liner)

Нужен чистый сервер на Debian или Ubuntu с root-доступом.

```bash
curl -fsSL https://raw.githubusercontent.com/klion-gh/stillhere/main/install.sh | sudo bash
```

Запускайте это в обычной SSH-сессии — установщик задаёт вопросы. Если терминала нет (скрипт, CI), передайте ответы переменными окружения:

```bash
curl -fsSL https://raw.githubusercontent.com/klion-gh/stillhere/main/install.sh -o install.sh
STILLHERE_NODE_PASSWORD='ваш-пароль' STILLHERE_DOMAIN='' sudo -E bash install.sh
```

Установщик сам:
- поставит Docker, если его нет;
- спросит пароль узла и (опционально) домен;
- сгенерирует все секреты;
- настроит TLS — self-signed сертификат с TOFU-проверкой на клиенте, если домена нет, либо ваш существующий сертификат/новый через Let's Encrypt, если домен есть;
- предложит настроить push-уведомления (можно пропустить и включить позже);
- поднимет весь стек (`docker compose up -d`).

В конце выведет адрес узла (и, если сертификат self-signed, его SHA-256 отпечаток) — это и нужно будет ввести в приложении StillHere на экране подключения.

Подробности того, что именно делает установщик, и на какие переменные окружения можно повлиять — см. [install.sh](install.sh) и [docker/.env.example](docker/.env.example).

---

## Структура репозитория

```
server/     Fastify + TypeScript + Prisma backend (REST + WebSocket)
client/     Flutter app (Android + Windows)
docker/     docker-compose для деплоя узла (postgres, backend, caddy, coturn)
install.sh  one-liner установщик узла
```

## Что есть и чего пока нет

Есть: пейринг с узлом по паролю, регистрация/логин по тегу, 1:1 текстовый чат в реальном времени с историей, 1:1 аудиозвонки через WebRTC (STUN/TURN для обхода NAT), TLS без домена через self-signed + TOFU pinning на клиенте.

Пока нет (сознательно отложено): групповые чаты, push-уведомления. Из второго следует ограничение — **входящий звонок или сообщение долетят, только пока приложение открыто** (на Android — пока живёт процесс/foreground service). Полноценные пуши через Firebase Cloud Messaging — следующий шаг.

---

## Локальная разработка

### Backend

Нужен Docker (для Postgres) и Node.js 22+.

```bash
cd server
cp .env.example .env
# впишите в .env любой NODE_SETUP_PASSWORD — этим паролем клиент будет
# спариваться с локальным сервером через экран подключения
npm install
docker run -d --name stillhere-postgres -e POSTGRES_USER=stillhere -e POSTGRES_PASSWORD=stillhere -e POSTGRES_DB=stillhere -p 5432:5432 postgres:16-alpine
npm run prisma:migrate    # создаст таблицы
npm run dev                # http://localhost:3000, healthcheck: GET /health
```

### Client (Flutter)

Flutter SDK не входил в текущее окружение сборки — исходники (`pubspec.yaml`, `lib/`) написаны, но нативные обёртки `android/` и `windows/` генерируются самим Flutter CLI и в репозитории их пока нет. Один раз перед первым запуском:

```bash
cd client
flutter create . --platforms=android,windows --org com.stillhere   # сгенерирует android/ и windows/, не тронет lib/
flutter pub get
flutter run -d windows      # или -d <android-device-id>
```

Адрес сервера **не** зашивается в сборку — при первом запуске приложение спросит адрес узла и пароль узла (экран подключения) и запомнит их локально. Для локальной разработки укажите там `localhost:3000` (Android-эмулятору вместо `localhost` может понадобиться `10.0.2.2`) и `NODE_SETUP_PASSWORD` из `server/.env`.

**Важно про разрешения на микрофон** — `flutter create` не включает их по умолчанию, без этого шага звонки не будут работать:

- **Android** (`android/app/src/main/AndroidManifest.xml`): добавьте внутри `<manifest>` перед `<application>`:
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.BLUETOOTH" />
  ```
- **Windows** (`windows/runner/Runner.rc` / capabilities не требуются для Win32-сборки без MSIX-упаковки — `flutter_webrtc` на Windows desktop использует системный API напрямую; если будете паковать в MSIX, добавьте capability `microphone` в `Package.appxmanifest`).

---

## Ручной деплой на VPS (без установщика)

Если не хотите использовать `install.sh` — например, сервер не Debian/Ubuntu — можно повторить его шаги руками; сам скрипт [install.sh](install.sh) написан достаточно линейно, чтобы служить документацией. Коротко:

1. Docker + Docker Compose на сервере.
2. `git clone` этого репозитория.
3. `cp docker/.env.example docker/.env` и заполнить: `NODE_HOST` (домен или IP), при наличии домена — `DOMAIN`/`ACME_EMAIL`, секреты (`openssl rand -hex 32` для каждого `*_SECRET`), `NODE_SETUP_PASSWORD` — пароль, который вы дадите друзьям.
4. Создать `docker/Caddyfile` — в репозитории его нет, есть только [docker/Caddyfile.example](docker/Caddyfile.example) с тремя готовыми вариантами (домен + Let's Encrypt, IP + self-signed, свой сертификат). Файл специально не отслеживается git: иначе обновление кода затирало бы TLS-настройки узла. Генерация self-signed сертификата — обычный `openssl req -x509 ...`, пример есть в `install.sh`.
5. Открыть порты в файрволе (`ufw` пример):
   ```bash
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw allow 3478/tcp
   ufw allow 3478/udp
   ufw allow 5349/tcp
   ufw allow 5349/udp
   ufw allow 49160:49200/udp   # TURN relay range, см. docker-compose.yml
   ```
   coturn запущен с `network_mode: host`, поэтому его порты не идут через `docker-compose ports:` — открывать нужно именно в файрволе хоста.
6. `cd docker && docker compose up -d --build`. При первом старте backend-контейнер сам применит миграции Prisma и захеширует `NODE_SETUP_PASSWORD` в базу (дальше эта переменная больше не используется, можно оставить в `.env` — она идемпотентна).
7. Проверка: `curl https://ваш-адрес/health` → `{"status":"ok"}`.

### Обновление после изменений в коде

```bash
git pull
cd docker && docker compose up -d --build backend
```

Postgres-данные хранятся в именованном volume `stillhere_postgres_data` и не теряются между пересборками.

Обновляетесь с версии 0.10.0 или раньше? До 0.11.0 `docker/Caddyfile` лежал в
репозитории, и `git pull` заменит ваш рабочий конфиг на шаблон — Caddy после
этого не стартует (`unrecognized global option: tls`), а узел перестанет
отвечать по HTTPS. Один раз сделайте так:

```bash
cp docker/Caddyfile /tmp/Caddyfile.bak
git checkout -- docker/Caddyfile && git pull
cp /tmp/Caddyfile.bak docker/Caddyfile
cd docker && docker compose up -d --build
```

Дальше файл не отслеживается и обновления его не трогают. Сертификаты в
`docker/certs/` не затрагивались никогда, так что закреплённый в приложениях
отпечаток остаётся прежним и переподключаться заново не нужно.

## Push-уведомления (необязательно)

Без этого раздела узел полностью работоспособен — просто на Android звонки и сообщения доходят, только пока приложение открыто. Чтобы они приходили и в фоне, нужен Firebase Cloud Messaging.

**Пересобирать приложение не нужно.** Узел сам сообщает приложению, каким проектом Firebase пользоваться, поэтому готовый APK из релизов работает с любым узлом — с вашим проектом, а не с чужим.

У каждого узла должен быть **свой** проект Firebase: ключ от чужого проекта не подойдёт, а свой даёт право отправлять push вашим пользователям — поэтому он и не хранится в репозитории.

Установщик предложит настроить push сразу. Если вы пропустили этот шаг — включите позже в любой момент:

```bash
cd ~/stillhere && ./enable-push.sh
```

Скрипт скажет, каких файлов не хватает и какие именно команды выполнить. Что нужно сделать:

1. Создайте проект на [console.firebase.google.com](https://console.firebase.google.com).
2. Добавьте в него Android-приложение с package name **`com.stillhere.stillhere`** (именно такой, иначе готовый APK не сможет работать с вашим проектом) и скачайте `google-services.json`.
3. Настройки проекта → «Сервисные аккаунты» → «Создать закрытый ключ».
4. Скопируйте оба файла на сервер — **со своего компьютера**, они скачиваются в браузере:
   ```bash
   scp google-services.json root@ВАШ_СЕРВЕР:~/stillhere/docker/secrets/
   scp ваш-ключ.json root@ВАШ_СЕРВЕР:~/stillhere/docker/secrets/firebase-service-account.json
   ```
5. `cd ~/stillhere && ./enable-push.sh`

В логах появится `push: firebase initialised` и `push: client config loaded`. Если файлов нет — `background delivery disabled`, это не ошибка: узел работает, просто без фоновой доставки.

Приватный ключ приложению **не передаётся** — из четырёх значений в `google-services.json` секретов нет (они и так лежат внутри любого опубликованного APK), а отправлять push может только сервер.

## Лицензия

[MIT](LICENSE).
