# Как поставить WristPlayer на iPhone и Apple Watch

iOS- и watchOS-приложения можно подписать и установить только инструментами Apple. Код уже собирается
в облаке (GitHub Actions, macOS + Xcode 26), поэтому Mac нужен только для одного из вариантов ниже.

| Вариант | Нужно | Цена | Срок жизни установки |
|---|---|---|---|
| **A. TestFlight** (рекомендую) | Apple Developer Program, Windows-ПК | $99/год | 90 дней на сборку, обновление одной кнопкой |
| **B. iMac 2013 + OpenCore Legacy Patcher** | ваш iMac (8 ГБ памяти), бесплатный Apple ID, вечер на настройку | бесплатно | 7 дней, потом повторный запуск скрипта |
| **C. Чужой современный Mac** | доступ к Mac на час | бесплатно | 7 дней (с платным аккаунтом — год) |

> **Почему не Sideloadly / AltStore / xtool с Windows.** Эти программы подписывают только iPhone-приложение
> и его расширения. Приложение для Apple Watch лежит внутри отдельно, и для него нужен свой профиль,
> в который вписаны сами часы. Эти инструменты так не умеют (в xtool, например, подписываются только
> расширения из папок `PlugIns` и `Extensions`). Итог: iPhone-часть встанет, а на часах приложения не будет.

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
Репозиторий <https://github.com/abc1113def/wristplayer> → **Settings** → **Secrets and variables** → **Actions** →
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

## Вариант B — старый Mac через OpenCore Legacy Patcher

Для **iMac 21.5" Late 2013** всё расписано по шагам в [MAC_SETUP.md](MAC_SETUP.md). Коротко:
OpenCore Legacy Patcher → macOS Sequoia → **Xcode 26.3** (последний для Sequoia) → `bash scripts/mac-install.sh`.
Бесплатный Apple ID подходит, но подпись живёт 7 дней — потом скрипт запускается ещё раз.

---

## Вариант C — разово воспользоваться современным Mac

Шаги 3–6 из [MAC_SETUP.md](MAC_SETUP.md) на любом Mac с macOS 15.6+ (на macOS Tahoe подойдёт и Xcode новее) (свой, друга, на работе). С бесплатным Apple ID
установка проживёт 7 дней; если оформить Developer Program — год.

---

## После установки

1. Откройте WristPlayer на iPhone → «+» → выберите песни (или «Поделиться» → WristPlayer из Telegram/почты,
   или перетащите файлы в Apple Devices/iTunes на Windows → Файлы → WristPlayer).
2. У каждой песни значок часов: включён — песня поедет на часы. Передача идёт в фоне, быстрее всего —
   когда часы на зарядке рядом с телефоном.
3. Подключите Bluetooth-наушники к часам, откройте WristPlayer на часах и выберите песню.
   Колёсико Digital Crown — громкость; управлять можно и из «Исполняется».
