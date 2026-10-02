# Как поставить WristPlayer на iPhone и Apple Watch

iOS- и watchOS-приложения можно подписать и установить только инструментами Apple. Код уже собирается
в облаке (GitHub Actions, macOS + Xcode 26), поэтому Mac нужен только для одного из вариантов ниже.

| Вариант | Нужно | Цена | Срок жизни установки |
|---|---|---|---|
| **A. TestFlight** (рекомендую) | Apple Developer Program, Windows-ПК | $99/год | 90 дней на сборку, обновление одной кнопкой |
| **B. Mac 2012 + OpenCore Legacy Patcher** | старый Mac, бесплатный Apple ID | бесплатно | 7 дней, потом переустановка из Xcode |
| **C. Чужой современный Mac** | доступ к Mac на час | бесплатно | 7 дней (с платным аккаунтом — год) |

> Программы для «сайдлоада» под Windows (Sideloadly, AltStore и т.п.) рассчитаны на iPhone-приложения:
> часть для Apple Watch они надёжно не ставят. Поэтому их здесь нет.

---

## Вариант A — TestFlight (без Mac)

Сборка, подпись и загрузка выполняются на GitHub. Вы только один раз настраиваете аккаунты.

### 1. Подписка разработчика
1. Зайдите на <https://developer.apple.com/programs/enroll/> со своим Apple ID и оформите Apple Developer Program.
   Одобрение занимает от нескольких часов до пары дней.
2. Когда подписка активна: <https://developer.apple.com/account> → **Membership details** → скопируйте **Team ID**
   (10 символов, например `A1B2C3D4E5`).

### 2. Ключ App Store Connect API
1. <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → «+».
2. Имя — любое (например `GitHub`), роль — **Admin** (нужна, чтобы CI сам создал сертификаты и профили).
3. Скачайте файл `AuthKey_XXXXXXXXXX.p8` — **скачать его можно только один раз**, сохраните.
4. Запишите **Key ID** (в таблице ключей) и **Issuer ID** (над таблицей).

### 3. Секреты в GitHub
Репозиторий <https://github.com/abc1113def/wrist-player> → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**. Добавьте четыре секрета:

| Имя | Значение |
|---|---|
| `TEAM_ID` | Team ID из шага 1 |
| `ASC_KEY_ID` | Key ID из шага 2 |
| `ASC_ISSUER_ID` | Issuer ID из шага 2 |
| `ASC_KEY_P8_BASE64` | содержимое `.p8` в base64 (см. ниже) |

Как получить base64 в PowerShell (результат окажется в буфере обмена — вставьте его в поле секрета):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard
```

### 4. Первая загрузка
1. GitHub → **Actions** → **TestFlight** → **Run workflow**. Через ~15 минут сборка уйдёт в App Store Connect.
   При первом запуске CI сам зарегистрирует идентификаторы `io.github.abc1113def.wristplayer`
   и `io.github.abc1113def.wristplayer.watchkitapp`.
2. Если шаг упал с ошибкой про отсутствующее приложение — создайте запись приложения:
   App Store Connect → **Apps** → «+» → **New App**: платформа iOS, имя `WristPlayer` (если имя занято — любое другое,
   например «WristPlayer Офлайн»), основной язык — русский, Bundle ID — `io.github.abc1113def.wristplayer`,
   SKU — любое (`wristplayer`). Затем снова **Run workflow**.

### 5. Установка на телефон и часы
1. App Store Connect → ваше приложение → **TestFlight** → **Internal Testing** → «+» → создайте группу и добавьте себя.
2. На iPhone поставьте приложение **TestFlight** из App Store и откройте приглашение из письма.
3. Установите WristPlayer. Приложение для часов поставится автоматически (если выключено автоустановка —
   приложение **Watch** на iPhone → **Мои часы** → WristPlayer → **Установить**).

Сборка TestFlight работает 90 дней. Новая версия — снова **Run workflow** (номер сборки растёт сам).

---

## Вариант B — Mac 2012 через OpenCore Legacy Patcher

Официально Mac 2012 года обновляется только до macOS Catalina и Xcode 12.4 — этого мало: проект использует
iOS 18 SDK и Swift-макросы (нужен Xcode 16+), а для часов и iPhone на 27-й версии нужен свежий Xcode.

[OpenCore Legacy Patcher](https://dortania.github.io/OpenCore-Legacy-Patcher/) позволяет поставить на такие Mac
macOS Sequoia 15, а на ней работает **Xcode 26** (требует macOS 15.6+). Это бесплатно, но:
- сделайте резервную копию Mac перед установкой;
- на старом железе всё будет заметно медленнее, возможны глюки графики;
- бесплатная подпись живёт **7 дней**, потом приложение нужно переустановить из Xcode.

Если решитесь:
1. Поставьте macOS Sequoia через OpenCore Legacy Patcher (по их инструкции).
2. Поставьте Xcode 26 (App Store или <https://developer.apple.com/download/all/>), откройте его один раз,
   согласитесь с лицензией, добавьте Apple ID: **Xcode → Settings → Accounts**.
3. В Терминале:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install xcodegen gh
   gh auth login
   gh repo clone abc1113def/wrist-player && cd wrist-player
   ```
4. Откройте `project.yml` и замените `APP_BUNDLE_ID` на свой уникальный, например `com.ivanov.wristplayer`
   (бесплатный аккаунт не может использовать чужой идентификатор). Затем:
   ```bash
   xcodegen generate && open WristPlayer.xcodeproj
   ```
5. В Xcode для **обеих** целей (WristPlayer и WristPlayerWatch): **Signing & Capabilities** → **Team** → ваш
   «Personal Team».
6. На iPhone и на часах включите **Режим разработчика**: Настройки → Конфиденциальность и безопасность →
   Режим разработчика (на часах — то же в настройках часов). Подключите iPhone кабелем, нажмите «Доверять».
7. Вверху Xcode выберите схему **WristPlayer** и ваш iPhone → ▶︎ Run. Затем схему **WristPlayerWatch** и часы → ▶︎ Run.
8. На iPhone: Настройки → Основные → VPN и управление устройством → ваш Apple ID → «Доверять».

Если Xcode 26 не увидит iPhone/часы на 27-й версии — значит, без нового Xcode не обойтись, и остаётся вариант A или C.

---

## Вариант C — разово воспользоваться современным Mac

Те же шаги 2–8 из варианта B на любом Mac с macOS 15.6+ (свой, друга, на работе). С бесплатным Apple ID
установка проживёт 7 дней; если оформить Developer Program — год.

---

## После установки

1. Откройте WristPlayer на iPhone → «+» → выберите песни (или «Поделиться» → WristPlayer из Telegram/почты,
   или перетащите файлы в Apple Devices/iTunes на Windows → Файлы → WristPlayer).
2. У каждой песни значок часов: включён — песня поедет на часы. Передача идёт в фоне, быстрее всего —
   когда часы на зарядке рядом с телефоном.
3. Подключите Bluetooth-наушники к часам, откройте WristPlayer на часах и выберите песню.
   Колёсико Digital Crown — громкость; управлять можно и из «Исполняется».
