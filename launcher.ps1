<#
  Claude Code Launcher
  Удобный запуск Claude Code: выбор проекта, продолжение сессий, настройки.

  Установка:  дважды щёлкните Install.cmd
  Удаление:   Uninstall.cmd  (или «Настройки → Удалить лаунчер»)

  Командная строка:
    launcher.ps1             запустить лаунчер
    launcher.ps1 -Install    установить (ярлыки, профиль Windows Terminal)
    launcher.ps1 -Uninstall  удалить

  Обновления и скиллы берутся из GitHub-репозитория ($DefaultSource ниже или «Настройки → Источник
  обновлений»). Манифест manifest.json в корне репозитория собирает tools\Make-Manifest.ps1.
#>
param([switch]$Install, [switch]$Uninstall, [switch]$Quiet, [switch]$Updated)

$ErrorActionPreference = 'Stop'
$AppVersion   = '2.0.0'
# Репозиторий с обновлениями и каталогом скиллов: 'владелец/репозиторий' или 'владелец/репозиторий@ветка'.
$DefaultSource = '20launcher25/20launcher25'
$AppId        = 'ClaudeCodeLauncher'
$AppName      = 'Claude Code Launcher'
$AppDir       = Join-Path $env:LOCALAPPDATA $AppId
$AppScript    = Join-Path $AppDir 'launcher.ps1'
$SettingsFile = Join-Path $AppDir 'settings.json'
$FragmentDir  = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\$AppId"
$ProfileName  = 'Claude Code Launcher'
$SchemeName   = 'Claude Launcher'
$ShortcutName = 'Claude Code Launcher.lnk'
$DocsUrl      = 'https://docs.claude.com/en/docs/claude-code/setup'
$GitUrl       = 'https://git-scm.com/downloads/win'
$InstallCmd   = 'irm https://claude.ai/install.ps1 | iex'
$UsageFile    = Join-Path $AppDir 'usage.json'      # сюда пишет мод usage-mod
$ModName      = 'usage-mod'                         # мод: пишет лимиты в usage.json
$BarModName   = 'limits-bar'                        # мод: строка лимитов над полем ввода Claude
$UsagePageUrl = 'https://claude.ai/settings/usage'
$SkillsDir    = Join-Path $env:USERPROFILE '.claude\skills'

try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::InputEncoding  = [Text.Encoding]::UTF8
} catch {}

# Windows Terminal умеет всё; в обычной консоли включаем ANSI-цвета и берём простые символы.
$Fancy = [bool]$env:WT_SESSION
if (-not $Fancy) {
    try {
        Add-Type -Namespace CCL -Name VT -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        $h = [CCL.VT]::GetStdHandle(-11); $m = [uint32]0
        if ([CCL.VT]::GetConsoleMode($h, [ref]$m)) { [void][CCL.VT]::SetConsoleMode($h, $m -bor 4) }
    } catch {}
}

# ═════════════════════════ настройки ═════════════════════════
function Get-DefaultLang {
    $c = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if (@('ru', 'kk', 'uk', 'be', 'ky', 'uz', 'tg') -contains $c) { 'ru' } else { 'en' }
}
$Cfg = [ordered]@{
    lang = (Get-DefaultLang); projects = 'auto'; defaultAction = 'new'
    permissionMode = 'default'; model = 'default'; greeting = $true; showLimits = $true; limitsBar = $true
    hidden = @(); firstRunDone = $false; verExe = ''; verStamp = ''; version = ''
    autoUpdate = $true; updateSource = ''; skipVersion = ''; lastCheck = ''; latestVersion = ''
    skills = @{}; extraPlugins = @(); extraUsageFiles = @()
}
function Load-Settings {
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $o = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { if ($Cfg.Contains($p.Name)) { $Cfg[$p.Name] = $p.Value } }
        } catch { $script:SettingsError = $_.Exception.Message }
    }
    $Cfg.hidden = @($Cfg.hidden | Where-Object { $_ })
    $Cfg.extraPlugins = @($Cfg.extraPlugins | Where-Object { $_ })
    $Cfg.extraUsageFiles = @($Cfg.extraUsageFiles | Where-Object { $_ })
    # скиллы, поставленные из лаунчера: имя -> ревизия
    $sk = @{}
    if ($Cfg.skills -is [Collections.IDictionary]) { foreach ($k in $Cfg.skills.Keys) { $sk[[string]$k] = [string]$Cfg.skills[$k] } }
    elseif ($Cfg.skills) { foreach ($p in $Cfg.skills.PSObject.Properties) { $sk[$p.Name] = [string]$p.Value } }
    $Cfg.skills = $sk
}
$SettingsError = ''
function Save-Settings {
    if ($SettingsError) { return }   # не затираем повреждённый файл, пока пользователь его не увидел
    try {
        if (-not (Test-Path -LiteralPath $AppDir)) { New-Item -ItemType Directory -Force -Path $AppDir | Out-Null }
        [IO.File]::WriteAllText($SettingsFile, ($Cfg | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    } catch {}
}
$Opts = @{
    model          = @('default', 'fable', 'opus', 'sonnet')
    permissionMode = @('default', 'manual', 'acceptEdits', 'auto', 'plan')
    lang           = @('ru', 'en')
    showLimits     = @($true, $false)
    limitsBar      = @($true, $false)
    projects       = @('auto', '5', '8', '12')
    defaultAction  = @('new', 'continue')
    greeting       = @($true, $false)
    autoUpdate     = @($true, $false)
}

# ═════════════════════════ тексты ═════════════════════════
$Strings = @{
ru = @{
    greet_morning = 'Доброе утро'; greet_day = 'Добрый день'; greet_evening = 'Добрый вечер'; greet_night = 'Доброй ночи'
    home_sub = 'Выберите проект или откройте новую папку.'
    search_hint = '/ начните печатать, чтобы найти проект'; nothing = 'Ничего не найдено'
    sec_recent = 'Недавние проекты'; fit_note = '{0} из {1} · поиск покажет все'; found = 'найдено: {0}'
    no_projects = 'Проектов пока нет. Откройте любую папку ниже'
    sec_more = 'Ещё'; desktop = 'Рабочий стол'; browse = 'Открыть другую папку…'; browse_meta = 'выбор в Проводнике'
    settings = 'Настройки'; settings_meta = 'модель, режим, язык'; exit = 'Выход'
    k_select = 'выбор'; k_open = 'открыть'; k_search = 'поиск'; k_hide = 'скрыть'; k_exit = 'выход'; k_back = 'назад'
    k_run = 'запуск'; k_hot = 'быстрые клавиши'; k_change = 'изменить'; k_done = 'готово'
    sessions = @('сессия', 'сессии', 'сессий'); days = @('день', 'дня', 'дней')
    just_now = 'только что'; min_ago = '{0} мин назад'; h_ago = '{0} ч назад'; yesterday = 'вчера'; days_ago = '{0} назад'
    new_project = 'Новый проект'; no_sessions = 'сессий здесь ещё не было'; last_x = 'последняя {0}'
    launch_with = 'запуск: {0}'
    sec_start = 'Начать'; new_session = 'Новая сессия'; new_session_sub = 'чистый контекст, начать с нуля'
    continue = 'Продолжить последнюю'; last_conv = 'последний разговор'
    sec_recent_sessions = 'Недавние сессии'; all_sessions = 'Все сессии…'; all_sessions_sub = 'список с поиском и превью'
    sec_folder = 'Папка'; open_explorer = 'Открыть в Проводнике'; back_projects = 'К списку проектов'
    pick_title = 'Выберите папку проекта'; pick_ok = 'Открыть в Claude'
    start_failed = 'Не удалось запустить Claude Code:'; press_any = 'Нажмите любую клавишу'
    settings_title = 'Настройки'; settings_sub = 'Сохраняются сразу. Значение меняют ← → или Enter.'
    welcome_title = 'Добро пожаловать!'; welcome_sub = 'Настройте лаунчер под себя. Всё можно поменять позже в «Настройках».'
    sec_launch = 'Запуск Claude'; sec_view = 'Интерфейс'; sec_tools = 'Обслуживание'
    s_model = 'Модель'; s_model_sub = 'для новых и продолженных сессий'
    s_perm = 'Режим разрешений'; s_perm_sub = 'что Claude может делать без вопросов'
    s_lang = 'Язык'; s_lang_sub = 'язык лаунчера'
    s_projects = 'Проектов на главном'; s_projects_sub = 'сколько недавних проектов показывать'
    s_default = 'Выбрано в проекте'; s_default_sub = 'какой пункт подсвечен при открытии проекта'
    s_greeting = 'Приветствие'; s_greeting_sub = '«Добрый день!» на главном экране'
    s_limits = 'Лимиты на главном'; s_limits_sub = 'полоски «5 часов» и «Неделя» в лаунчере'
    s_bar = 'Строка лимитов в Claude'; s_bar_sub = 'модель, контекст и лимиты над полем ввода'
    lim_5h = '5 часов'; lim_week = 'Неделя'; lim_spend = 'Траты'; lim_short_5h = '5 ч'; lim_short_week = 'неделя'
    lim_reset = 'сброс {0}'; lim_reset_done = 'уже сброшен'; lim_tomorrow = 'завтра'; lim_updated = 'обновлено {0}'
    lim_wait = 'Лимиты появятся после первого ответа Claude в сессии из лаунчера'; lim_none = 'Лимиты подписки не пришли (вход по API-ключу?)'
    val_default = 'как в Claude Code'; val_auto = 'по высоте окна'; val_on = 'вкл'; val_off = 'выкл'
    perm_manual = 'спрашивать всё'; perm_accept = 'сам правит файлы'; perm_auto = 'авто'; perm_plan = 'только план'
    update_claude = 'Обновить Claude Code'; update_sub = 'скачать и поставить свежую версию'
    fit_window = 'Подогнать окно под экран'; fit_window_sub = 'пересоздать ярлыки под этот монитор'
    fit_done = 'Ярлыки обновлены. Новый размер окна будет при следующем запуске'
    unhide = 'Вернуть скрытые проекты'; unhide_meta = 'скрыто: {0}'; unhide_done = 'Скрытые проекты снова в списке'
    open_dir = 'Открыть папку лаунчера'
    repair = 'Что-то сломалось? Починить с Claude'; repair_sub = 'Claude прочитает REPAIR.md, найдёт и исправит проблему'
    repair_prompt = 'Прочитай REPAIR.md в этой папке и действуй по нему: найди, что сломано в Claude Code Launcher на этом компьютере, исправь и проверь.'
    copy_prompt = 'Скопировать промт для починки'; copy_prompt_sub = 'вставьте его в Claude Code или на claude.ai'
    copied = 'Промт для починки скопирован в буфер обмена'
    uninstall = 'Удалить лаунчер'; uninstall_sub = 'Claude Code и ваши сессии останутся'
    uninstall_q = 'Удалить Claude Code Launcher?'; yes_delete = 'Да, удалить'; cancel = 'Отмена'
    done = 'Готово'
    missing_title = 'Claude Code не найден'; missing_sub = 'Для работы лаунчера нужен установленный Claude Code.'
    install_claude = 'Установить Claude Code'; install_claude_sub = 'официальный установщик Anthropic'
    open_docs = 'Инструкция по установке'; check_again = 'Проверить снова'
    get_git = 'Скачать Git for Windows'; get_git_sub = 'Claude Code нужен Git в Windows'
    installing = 'Запускаю официальный установщик Claude Code…'
    not_found_after = 'Claude Code пока не виден. Закройте окно и запустите лаунчер заново.'
    i_title = 'Установка'; i_wt = 'Windows Terminal'; i_wt_missing = 'не найден, будет обычное окно консоли'
    i_claude = 'Claude Code'; i_claude_missing = 'не найден, лаунчер предложит установить его при первом запуске'
    i_git = 'Git for Windows'; i_git_missing = 'не найден, а он нужен Claude Code'
    i_files = 'Файлы лаунчера'; i_profile = 'Профиль Windows Terminal'; i_shortcuts = 'Ярлыки: рабочий стол и меню «Пуск»'
    i_done = 'Готово! На рабочем столе появился ярлык «Claude Code Launcher».'
    i_launch = 'Enter: запустить сейчас     Esc: закрыть'
    u_title = 'Удаление'; u_q = 'Удалить лаунчер? Claude Code и ваши сессии останутся.  Y: да, любая другая клавиша: нет'
    u_done = 'Лаунчер удалён.'; u_cancel = 'Отменено.'
    back = 'Назад'; yes = 'есть'; no = 'нет'
    sec_account = 'Аккаунт и лимиты'; info = 'Сведения и лимиты'; info_sub = 'аккаунт, план, лимиты подписки, версии программ'
    info_title = 'Сведения'; info_hdr_sub = 'Аккаунт Claude, лимиты подписки и версии программ.'
    inf_account = 'Аккаунт'; inf_limits = 'Лимиты'; inf_apps = 'Программы'
    inf_plan = 'План'; inf_since = 'подписка с {0}'; inf_extra = 'Доп. использование'; inf_role = 'роль: {0}'
    inf_no_account = 'Данных аккаунта нет: вход по API-ключу или Claude Code ещё не запускался'
    inf_launcher = 'Лаунчер'; inf_source = 'обновления: {0}'; inf_checked = 'проверено {0}'; inf_never = 'ещё не проверялось'
    inf_skills = 'Скиллы'; inf_skills_val = 'установлено: {0}  ·  из лаунчера: {1}'
    refresh = 'Обновить данные'; refresh_sub = 'перечитать лимиты и аккаунт'
    open_usage = 'Лимиты на claude.ai'; open_usage_sub = 'страница использования в браузере'
    sec_updates = 'Обновления'
    check_upd = 'Проверить обновления'; check_upd_sub = 'новая версия лаунчера из GitHub-репозитория'
    upd_meta_latest = 'v{0} · последняя'; upd_meta_new = 'вышла v{0}'; upd_meta_none = 'источник не задан'; upd_meta_err = 'ошибка'
    s_autoUpdate = 'Проверять при запуске'; s_autoUpdate_sub = 'тихо искать обновление при каждом запуске'
    upd_source = 'Источник обновлений'; upd_source_sub = 'GitHub-репозиторий, откуда берутся обновления и скиллы'
    src_prompt = 'Введите GitHub-репозиторий «владелец/репозиторий» (можно «@ветка» или ссылку github.com/…) или путь к папке.'
    src_hint = 'Пустой Enter оставит как есть, «-» вернёт значение по умолчанию.'
    src_current = 'Сейчас: {0}'; src_none = 'не задан'
    sec_skills = 'Скиллы'; skills = 'Установить скиллы'; skills_sub = 'каталог скиллов из репозитория лаунчера'; skills_meta = 'из лаунчера: {0}'
    skills_title = 'Скиллы'; skills_hdr_sub = 'Ставятся в ~/.claude/skills. Claude Code увидит их в новой сессии.'
    sk_catalog = 'Каталог'; sk_count = 'в каталоге: {0}'
    sk_installed = 'установлен'; sk_update = 'обновить'; sk_install = 'установить'; sk_local = 'есть свой'
    sk_install_all = 'Установить все'; sk_install_all_sub = 'поставить новые и обновить установленные'
    sk_open_dir = 'Открыть папку скиллов'; sk_reload = 'Обновить каталог'
    sk_installing = 'Устанавливаю скилл «{0}»…'
    sk_done = 'Скилл «{0}» установлен и появится в новой сессии Claude'; sk_removed = 'Скилл «{0}» удалён'; sk_uptodate = '«{0}» уже последней версии'
    sk_all_done = 'Установлено и обновлено: {0}'; sk_all_none = 'Всё уже установлено'
    sk_empty = 'В каталоге пока нет скиллов'; sk_loading = 'Загружаю каталог скиллов…'
    sk_overwrite_q = 'Заменить свой скилл «{0}»?'; sk_overwrite_sub = 'Такая папка уже есть в ~/.claude/skills, и поставлена она не из лаунчера.'; yes_replace = 'Да, заменить'
    sk_remove_q = 'Удалить скилл «{0}»?'; sk_remove_sub = 'Папка скилла будет удалена из ~/.claude/skills.'; yes_remove = 'Да, удалить'
    sk_not_ours = 'Этот скилл поставлен не из лаунчера, удалите его вручную'
    k_install = 'установить'; k_remove = 'удалить'
    upd_title = 'Обновление лаунчера'; upd_avail = 'Вышло обновление {0}'; upd_from_to = 'сейчас v{0}  {1}  станет v{2}'
    upd_home = 'Вышло обновление v{0}'; upd_home_hint = 'пункт «Обновить лаунчер» ниже'
    upd_item = 'Обновить лаунчер до v{0}'; upd_item_meta = 'новое'
    upd_whatsnew = 'Что нового'
    upd_install = 'Установить обновление'; upd_install_sub = 'скачать, проверить и перезапустить лаунчер'
    upd_later = 'Напомнить позже'; upd_skip = 'Пропустить эту версию'; upd_skip_sub = 'не напоминать, пока не выйдет следующая'
    upd_latest = 'У вас последняя версия v{0}'; upd_checking = 'Проверяю обновления…'
    upd_failed = 'Не удалось проверить: {0}'; upd_nosrc = 'Источник обновлений не задан. Укажите GitHub-репозиторий'
    upd_check_again = 'Проверить снова'
    upd_downloading = 'Скачиваю обновление v{0}'; upd_verify_fail = 'файл повреждён (контрольная сумма не сошлась)'
    upd_applied = 'Обновлено до v{0}. Перезапускаю…'; upd_done_notice = 'Лаунчер обновлён до v{0}'
    upd_bad_path = 'недопустимый путь в манифесте'
    health = 'Проверка компонентов'; health_sub = 'чего не хватает на этом компьютере и как это исправить'
    health_title = 'Проверка компонентов'; health_hdr_sub = 'Всё, что нужно лаунчеру, и где он это искал.'
    health_ok = 'Всё на месте'; health_meta = 'проблем: {0}'; health_home = 'Не хватает компонентов: {0}'; health_home_hint = 'пункт «Проверка компонентов» ниже'
    h_claude = 'Claude Code'; h_claude_bad = 'не найден. Искал: PATH, ~\.localin, npm. Без него сессии не запустятся'
    h_git = 'Git for Windows'; h_git_bad = 'не найден, а Claude Code в Windows нужен Git'
    h_wt = 'Windows Terminal'; h_wt_bad = 'не найден, поэтому лаунчер работает в обычной консоли и выглядит проще'
    h_mod = 'Мод «{0}»'; h_mod_bad = 'нет папки, искал в {0}'; h_mod_off = 'выключен в настройках'
    h_mod_usage = 'лимиты в лаунчере'; h_mod_bar = 'строка лимитов в Claude'
    h_repair = 'REPAIR.md'; h_repair_bad = 'нет файла инструкции для починки, искал в {0}'
    h_settings = 'Настройки'; h_settings_bad = 'settings.json повреждён, сейчас настройки по умолчанию и не сохраняются: {0}'
    h_profile = 'Профиль Windows Terminal'; h_profile_bad = 'нет файла профиля, ярлык может не открыться: {0}'
    h_shortcut = 'Ярлык на рабочем столе'; h_shortcut_bad = 'не найден: {0}'
    h_plugin = 'Свой мод'; h_plugin_bad = 'папка из extraPlugins не найдена: {0}'
    h_usagefile = 'Файл лимитов'; h_usagefile_bad = 'из extraUsageFiles не найден: {0}'
    h_skill = 'Скилл «{0}»'; h_skill_bad = 'был поставлен из лаунчера, но папки больше нет'
    h_installed = 'Установка'; h_portable = 'лаунчер запущен из {0}, а не из установленной копии. Запустите Install.cmd'
    h_source = 'Источник обновлений'; h_source_bad = 'не задан, обновления и скиллы недоступны'
    fix_download = 'Скачать недостающие файлы'; fix_download_sub = 'из репозитория обновлений, только то, чего нет'
    fix_download_none = 'Нечего скачивать: все файлы на месте или их нет в репозитории'; fix_downloaded = 'Скачано файлов: {0}'
    fix_nosrc = 'Источник обновлений не задан: скачайте архив лаунчера заново и запустите Install.cmd'
    fix_claude = 'Установить Claude Code'; fix_git = 'Скачать Git for Windows'; fix_wt = 'Windows Terminal в Microsoft Store'
    fix_reset = 'Сбросить настройки'; fix_reset_sub = 'старый файл сохранится как settings.bak.json'; fix_reset_done = 'Настройки сброшены, старые лежат в settings.bak.json'
    fix_profile = 'Пересоздать профиль и ярлыки'; fix_profile_done = 'Профиль и ярлыки пересозданы'
    fix_settings_open = 'Открыть settings.json'; fix_skills = 'Переустановить скиллы'
    fix_install = 'Установить лаунчер'; fix_install_sub = 'скопировать в %LOCALAPPDATA% и создать ярлыки'
    copy_report = 'Скопировать отчёт'; copy_report_sub = 'чтобы отправить тому, кто поможет, или вставить в Claude'; report_copied = 'Отчёт скопирован в буфер обмена'
    crash_title = 'Лаунчер остановился из-за ошибки'; crash_hint = 'Скопируйте текст выше или запустите Repair.cmd, и Claude найдёт и исправит причину.'
    crash_copied = 'Текст ошибки скопирован в буфер обмена.'
    policy = 'Политика использования'; policy_sub = 'правила, какие данные использует лаунчер, ответственность'
    err_404 = 'в «{0}» нет manifest.json: проверьте имя репозитория и ветку, что он публичный и manifest.json закоммичен'
    err_private = 'нет доступа к репозиторию: он приватный? Для обновлений он должен быть публичным'
    err_net = 'нет связи с GitHub: проверьте интернет, прокси или антивирус'
    err_nofile = 'файл не найден: {0}'
}
en = @{
    greet_morning = 'Good morning'; greet_day = 'Good afternoon'; greet_evening = 'Good evening'; greet_night = 'Good night'
    home_sub = 'Pick a project or open a new folder.'
    search_hint = '/ start typing to find a project'; nothing = 'Nothing found'
    sec_recent = 'Recent projects'; fit_note = '{0} of {1} · search shows all'; found = 'found: {0}'
    no_projects = 'No projects yet. Open any folder below'
    sec_more = 'More'; desktop = 'Desktop'; browse = 'Open another folder…'; browse_meta = 'pick in Explorer'
    settings = 'Settings'; settings_meta = 'model, mode, language'; exit = 'Quit'
    k_select = 'select'; k_open = 'open'; k_search = 'search'; k_hide = 'hide'; k_exit = 'quit'; k_back = 'back'
    k_run = 'start'; k_hot = 'shortcuts'; k_change = 'change'; k_done = 'done'
    sessions = @('session', 'sessions'); days = @('day', 'days')
    just_now = 'just now'; min_ago = '{0} min ago'; h_ago = '{0} h ago'; yesterday = 'yesterday'; days_ago = '{0} ago'
    new_project = 'New project'; no_sessions = 'no sessions here yet'; last_x = 'last {0}'
    launch_with = 'launch: {0}'
    sec_start = 'Start'; new_session = 'New session'; new_session_sub = 'fresh context, start from scratch'
    continue = 'Continue last'; last_conv = 'last conversation'
    sec_recent_sessions = 'Recent sessions'; all_sessions = 'All sessions…'; all_sessions_sub = 'searchable list with preview'
    sec_folder = 'Folder'; open_explorer = 'Open in Explorer'; back_projects = 'Back to projects'
    pick_title = 'Choose a project folder'; pick_ok = 'Open in Claude'
    start_failed = 'Could not start Claude Code:'; press_any = 'Press any key'
    settings_title = 'Settings'; settings_sub = 'Saved instantly. Change values with ← → or Enter.'
    welcome_title = 'Welcome!'; welcome_sub = 'Make the launcher yours. You can change all of this later in Settings.'
    sec_launch = 'Claude launch'; sec_view = 'Interface'; sec_tools = 'Maintenance'
    s_model = 'Model'; s_model_sub = 'for new and resumed sessions'
    s_perm = 'Permission mode'; s_perm_sub = 'what Claude may do without asking'
    s_lang = 'Language'; s_lang_sub = 'launcher language'
    s_projects = 'Projects on home'; s_projects_sub = 'how many recent projects to show'
    s_default = 'Preselected in project'; s_default_sub = 'which item is highlighted when a project opens'
    s_greeting = 'Greeting'; s_greeting_sub = '“Good afternoon!” on the home screen'
    s_limits = 'Limits on home'; s_limits_sub = '“5 hours” and “Week” bars in the launcher'
    s_bar = 'Limits line in Claude'; s_bar_sub = 'model, context and limits above the prompt'
    lim_5h = '5 hours'; lim_week = 'Week'; lim_spend = 'Spend'; lim_short_5h = '5h'; lim_short_week = 'week'
    lim_reset = 'resets {0}'; lim_reset_done = 'already reset'; lim_tomorrow = 'tomorrow'; lim_updated = 'updated {0}'
    lim_wait = 'Limits appear after Claude''s first reply in a session started from the launcher'; lim_none = 'No subscription limits reported (API key login?)'
    val_default = 'Claude Code default'; val_auto = 'fit window'; val_on = 'on'; val_off = 'off'
    perm_manual = 'ask for everything'; perm_accept = 'auto-accept edits'; perm_auto = 'auto'; perm_plan = 'plan only'
    update_claude = 'Update Claude Code'; update_sub = 'download and install the latest version'
    fit_window = 'Fit window to screen'; fit_window_sub = 'recreate shortcuts for this monitor'
    fit_done = 'Shortcuts updated. The new window size applies next launch'
    unhide = 'Restore hidden projects'; unhide_meta = 'hidden: {0}'; unhide_done = 'Hidden projects are back'
    open_dir = 'Open launcher folder'
    repair = 'Something broken? Fix it with Claude'; repair_sub = 'Claude reads REPAIR.md, finds the problem and fixes it'
    repair_prompt = 'Read REPAIR.md in this folder and follow it: find out what is broken in Claude Code Launcher on this computer, fix it and verify the fix.'
    copy_prompt = 'Copy the repair prompt'; copy_prompt_sub = 'paste it into Claude Code or claude.ai'
    copied = 'Repair prompt copied to the clipboard'
    uninstall = 'Uninstall launcher'; uninstall_sub = 'Claude Code and your sessions stay'
    uninstall_q = 'Uninstall Claude Code Launcher?'; yes_delete = 'Yes, uninstall'; cancel = 'Cancel'
    done = 'Done'
    missing_title = 'Claude Code not found'; missing_sub = 'The launcher needs Claude Code installed.'
    install_claude = 'Install Claude Code'; install_claude_sub = 'official Anthropic installer'
    open_docs = 'Installation guide'; check_again = 'Check again'
    get_git = 'Download Git for Windows'; get_git_sub = 'Claude Code needs Git on Windows'
    installing = 'Running the official Claude Code installer…'
    not_found_after = 'Claude Code is not visible yet. Close this window and start the launcher again.'
    i_title = 'Setup'; i_wt = 'Windows Terminal'; i_wt_missing = 'not found, a plain console window will be used'
    i_claude = 'Claude Code'; i_claude_missing = 'not found, the launcher will offer to install it on first run'
    i_git = 'Git for Windows'; i_git_missing = 'not found, and Claude Code needs it'
    i_files = 'Launcher files'; i_profile = 'Windows Terminal profile'; i_shortcuts = 'Shortcuts: desktop and Start menu'
    i_done = 'Done! A “Claude Code Launcher” shortcut is on your desktop.'
    i_launch = 'Enter: launch now     Esc: close'
    u_title = 'Uninstall'; u_q = 'Uninstall the launcher? Claude Code and your sessions stay.  Y: yes, any other key: no'
    u_done = 'Launcher removed.'; u_cancel = 'Cancelled.'
    back = 'Back'; yes = 'yes'; no = 'no'
    sec_account = 'Account and limits'; info = 'Info and limits'; info_sub = 'account, plan, subscription limits, versions'
    info_title = 'Info'; info_hdr_sub = 'Claude account, subscription limits and program versions.'
    inf_account = 'Account'; inf_limits = 'Limits'; inf_apps = 'Programs'
    inf_plan = 'Plan'; inf_since = 'subscribed since {0}'; inf_extra = 'Extra usage'; inf_role = 'role: {0}'
    inf_no_account = 'No account data: API key login, or Claude Code has not run yet'
    inf_launcher = 'Launcher'; inf_source = 'updates: {0}'; inf_checked = 'checked {0}'; inf_never = 'never checked'
    inf_skills = 'Skills'; inf_skills_val = 'installed: {0}  ·  from launcher: {1}'
    refresh = 'Refresh'; refresh_sub = 're-read limits and account'
    open_usage = 'Limits on claude.ai'; open_usage_sub = 'usage page in the browser'
    sec_updates = 'Updates'
    check_upd = 'Check for updates'; check_upd_sub = 'new launcher version from the GitHub repository'
    upd_meta_latest = 'v{0} · latest'; upd_meta_new = 'v{0} is out'; upd_meta_none = 'no source set'; upd_meta_err = 'error'
    s_autoUpdate = 'Check on startup'; s_autoUpdate_sub = 'quietly look for an update on every launch'
    upd_source = 'Update source'; upd_source_sub = 'GitHub repository for updates and skills'
    src_prompt = 'Enter a GitHub repository "owner/repo" (optionally "@branch" or a github.com/... link) or a folder path.'
    src_hint = 'Empty Enter keeps the current value, "-" restores the default.'
    src_current = 'Current: {0}'; src_none = 'not set'
    sec_skills = 'Skills'; skills = 'Install skills'; skills_sub = 'skill catalog from the launcher repository'; skills_meta = 'from launcher: {0}'
    skills_title = 'Skills'; skills_hdr_sub = 'Installed into ~/.claude/skills. Claude Code picks them up in a new session.'
    sk_catalog = 'Catalog'; sk_count = 'in catalog: {0}'
    sk_installed = 'installed'; sk_update = 'update'; sk_install = 'install'; sk_local = 'own copy'
    sk_install_all = 'Install all'; sk_install_all_sub = 'install new ones and update installed ones'
    sk_open_dir = 'Open skills folder'; sk_reload = 'Reload catalog'
    sk_installing = 'Installing skill "{0}"…'
    sk_done = 'Skill "{0}" installed, it appears in a new Claude session'; sk_removed = 'Skill "{0}" removed'; sk_uptodate = '"{0}" is already up to date'
    sk_all_done = 'Installed and updated: {0}'; sk_all_none = 'Everything is already installed'
    sk_empty = 'The catalog has no skills yet'; sk_loading = 'Loading the skill catalog…'
    sk_overwrite_q = 'Replace your own skill "{0}"?'; sk_overwrite_sub = 'This folder already exists in ~/.claude/skills and was not installed by the launcher.'; yes_replace = 'Yes, replace'
    sk_remove_q = 'Remove skill "{0}"?'; sk_remove_sub = 'The skill folder will be deleted from ~/.claude/skills.'; yes_remove = 'Yes, remove'
    sk_not_ours = 'This skill was not installed by the launcher, remove it manually'
    k_install = 'install'; k_remove = 'remove'
    upd_title = 'Launcher update'; upd_avail = 'Update {0} is out'; upd_from_to = 'now v{0}  {1}  will be v{2}'
    upd_home = 'Update v{0} is out'; upd_home_hint = 'see "Update launcher" below'
    upd_item = 'Update launcher to v{0}'; upd_item_meta = 'new'
    upd_whatsnew = 'What''s new'
    upd_install = 'Install update'; upd_install_sub = 'download, verify and restart the launcher'
    upd_later = 'Remind me later'; upd_skip = 'Skip this version'; upd_skip_sub = 'no reminders until the next one'
    upd_latest = 'You have the latest version v{0}'; upd_checking = 'Checking for updates…'
    upd_failed = 'Check failed: {0}'; upd_nosrc = 'No update source set. Enter a GitHub repository'
    upd_check_again = 'Check again'
    upd_downloading = 'Downloading update v{0}'; upd_verify_fail = 'file is corrupted (checksum mismatch)'
    upd_applied = 'Updated to v{0}. Restarting…'; upd_done_notice = 'Launcher updated to v{0}'
    upd_bad_path = 'invalid path in the manifest'
    health = 'Component check'; health_sub = 'what is missing on this computer and how to fix it'
    health_title = 'Component check'; health_hdr_sub = 'Everything the launcher needs, and where it looked for it.'
    health_ok = 'All in place'; health_meta = 'problems: {0}'; health_home = 'Missing components: {0}'; health_home_hint = 'see "Component check" below'
    h_claude = 'Claude Code'; h_claude_bad = 'not found. Looked in PATH, ~\.localin, npm. Sessions cannot start without it'
    h_git = 'Git for Windows'; h_git_bad = 'not found, and Claude Code on Windows needs Git'
    h_wt = 'Windows Terminal'; h_wt_bad = 'not found, so the launcher uses a plain console and looks simpler'
    h_mod = 'Mod "{0}"'; h_mod_bad = 'folder missing, looked in {0}'; h_mod_off = 'turned off in settings'
    h_mod_usage = 'limits in the launcher'; h_mod_bar = 'limits line in Claude'
    h_repair = 'REPAIR.md'; h_repair_bad = 'repair instructions missing, looked in {0}'
    h_settings = 'Settings'; h_settings_bad = 'settings.json is corrupted; defaults are in use and nothing is saved: {0}'
    h_profile = 'Windows Terminal profile'; h_profile_bad = 'profile file missing, the shortcut may not open: {0}'
    h_shortcut = 'Desktop shortcut'; h_shortcut_bad = 'not found: {0}'
    h_plugin = 'Custom mod'; h_plugin_bad = 'extraPlugins folder not found: {0}'
    h_usagefile = 'Limits file'; h_usagefile_bad = 'extraUsageFiles entry not found: {0}'
    h_skill = 'Skill "{0}"'; h_skill_bad = 'was installed by the launcher, but its folder is gone'
    h_installed = 'Installation'; h_portable = 'running from {0}, not the installed copy. Run Install.cmd'
    h_source = 'Update source'; h_source_bad = 'not set, updates and skills are unavailable'
    fix_download = 'Download missing files'; fix_download_sub = 'from the update repository, only what is missing'
    fix_download_none = 'Nothing to download: all files are in place or missing from the repository'; fix_downloaded = 'Files downloaded: {0}'
    fix_nosrc = 'No update source: download the launcher archive again and run Install.cmd'
    fix_claude = 'Install Claude Code'; fix_git = 'Download Git for Windows'; fix_wt = 'Windows Terminal in Microsoft Store'
    fix_reset = 'Reset settings'; fix_reset_sub = 'the old file is kept as settings.bak.json'; fix_reset_done = 'Settings reset, old ones are in settings.bak.json'
    fix_profile = 'Recreate profile and shortcuts'; fix_profile_done = 'Profile and shortcuts recreated'
    fix_settings_open = 'Open settings.json'; fix_skills = 'Reinstall skills'
    fix_install = 'Install the launcher'; fix_install_sub = 'copy to %LOCALAPPDATA% and create shortcuts'
    copy_report = 'Copy report'; copy_report_sub = 'to send to whoever helps you, or paste into Claude'; report_copied = 'Report copied to the clipboard'
    crash_title = 'The launcher stopped because of an error'; crash_hint = 'Copy the text above or run Repair.cmd and Claude will find and fix the cause.'
    crash_copied = 'The error text is copied to the clipboard.'
    policy = 'Usage policy'; policy_sub = 'rules, what data the launcher uses, liability'
    err_404 = 'no manifest.json in "{0}": check the repository name and branch, that it is public and manifest.json is committed'
    err_private = 'no access to the repository: is it private? It must be public for updates'
    err_net = 'cannot reach GitHub: check the internet connection, proxy or antivirus'
    err_nofile = 'file not found: {0}'
}
}
function T([string]$k) {
    $v = $Strings[[string]$Cfg.lang][$k]
    if ($null -eq $v) { $v = $Strings.ru[$k] }
    if ($null -eq $v) { return $k }
    $v
}
function TF([string]$k) { (T $k) -f $args }

# ═════════════════════════ оформление ═════════════════════════
$E = [char]27
function Rgb([string]$hex, [switch]$Bg) {
    $pick = [Convert]::ToInt32($hex.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
    $k = if ($Bg) { 48 } else { 38 }
    "$E[$k;2;$pick;$g;${b}m"
}
$Clay = Rgb '#D97757'; $Ivory = Rgb '#F0EEE6'; $Text2 = Rgb '#C9C6BC'; $Muted = Rgb '#8F8C84'
$Dim = Rgb '#64615B'; $Rule = Rgb '#3E3B37'; $Frame = Rgb '#9A5B45'; $SelBg = Rgb '#36302B' -Bg
$Green = Rgb '#8FB573'; $Amber = Rgb '#E8B964'; $Red = Rgb '#E06C5A'
$Bold = "$E[1m"; $NoBold = "$E[22m"; $R = "$E[0m"

function Ch([int]$code) { [string][char]$code }
$G = @{ Hz = Ch 0x2500; Vt = Ch 0x2502; Dot = Ch 0x00B7; Ell = Ch 0x2026; Up = Ch 0x2191; Down = Ch 0x2193; LQ = Ch 0x00AB; RQ = Ch 0x00BB; New = '+' }
if ($Fancy) {
    $G += @{ Star = Ch 0x273B; Bar = Ch 0x258C; TL = Ch 0x256D; TR = Ch 0x256E; BL = Ch 0x2570; BR = Ch 0x256F
             Proj = Ch 0x25C6; Cont = Ch 0x21BB; All = Ch 0x2261; Open = Ch 0x2197; Back = Ch 0x2190; Home = Ch 0x2302
             Browse = Ch 0x2026; Exit = Ch 0x00D7; Gear = Ch 0x25C7; Sess = Ch 0x00B7; Opt = Ch 0x25C7; Caret = Ch 0x258F
             Ok = Ch 0x2713; Err = Ch 0x2717; ArL = Ch 0x2039; ArR = Ch 0x203A; BarFull = Ch 0x2501; BarEmpty = Ch 0x2501
             Bul = Ch 0x2022; To = Ch 0x2192; Upd = Ch 0x2191; Skill = Ch 0x25C8; Info = Ch 0x25CE }
} else {
    $G += @{ Star = '*'; Bar = '|'; TL = Ch 0x250C; TR = Ch 0x2510; BL = Ch 0x2514; BR = Ch 0x2518
             Proj = '>'; Cont = '~'; All = '='; Open = '^'; Back = '<'; Home = '#'
             Browse = '.'; Exit = 'x'; Gear = '*'; Sess = '-'; Opt = '-'; Caret = '_'
             Ok = '+'; Err = 'x'; ArL = '<'; ArR = '>'; BarFull = '#'; BarEmpty = '-'
             Bul = '-'; To = '->'; Upd = '^'; Skill = '*'; Info = 'i' }
}

$AnsiRx = New-Object Text.RegularExpressions.Regex "\x1b\[[0-9;?]*[A-Za-z]"
function Vis([string]$s) { $AnsiRx.Replace($s, '').Length }
function PadTo([string]$s, [int]$w) { $n = $w - (Vis $s); if ($n -gt 0) { $s + (' ' * $n) } else { $s } }
function Spread([string]$left, [string]$right, [int]$w) {
    $n = $w - (Vis $left) - (Vis $right); if ($n -lt 1) { $n = 1 }
    $left + (' ' * $n) + $right
}
function FitEnd([string]$s, [int]$max) {
    if ($max -le 1) { return '' }; if ($s.Length -le $max) { return $s }
    $s.Substring(0, $max - 1).TrimEnd() + $G.Ell
}
function FitStart([string]$s, [int]$max) {
    if ($max -le 1) { return '' }; if ($s.Length -le $max) { return $s }
    $G.Ell + $s.Substring($s.Length - $max + 1)
}
function Clear-Screen { [Console]::Write("$R$E[2J$E[3J$E[H") }

# ═════════════════════════ текст и время ═════════════════════════
function Plural([int]$n, [object[]]$f) {
    if ($f.Count -eq 2) { if ($n -eq 1) { return "$n $($f[0])" } else { return "$n $($f[1])" } }
    $m10 = $n % 10; $m100 = $n % 100
    if ($m10 -eq 1 -and $m100 -ne 11) { return "$n $($f[0])" }
    if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return "$n $($f[1])" }
    "$n $($f[2])"
}
function Format-Ago([datetime]$t) {
    $d = (Get-Date) - $t
    if ($d.TotalMinutes -lt 1) { return (T 'just_now') }
    if ($d.TotalMinutes -lt 60) { return (TF 'min_ago' ([math]::Floor($d.TotalMinutes))) }
    if ($d.TotalHours -lt 24) { return (TF 'h_ago' ([math]::Floor($d.TotalHours))) }
    if ($d.TotalDays -lt 2) { return (T 'yesterday') }
    if ($d.TotalDays -lt 7) { return (TF 'days_ago' (Plural ([math]::Floor($d.TotalDays)) (T 'days'))) }
    $ci = if ($Cfg.lang -eq 'ru') { 'ru-RU' } else { 'en-US' }
    $t.ToString('d MMM', [Globalization.CultureInfo]::GetCultureInfo($ci))
}
function Format-Path([string]$p) {
    $h = $env:USERPROFILE
    if ($h -and $p.StartsWith($h, [StringComparison]::OrdinalIgnoreCase)) { $p = '~' + $p.Substring($h.Length) }
    $p
}
function Normalize-Path([string]$p) { if ($p.Length -gt 3) { $p.TrimEnd('\') } else { $p } }
function Leaf([string]$p) { $l = Split-Path -Leaf $p; if ([string]::IsNullOrEmpty($l)) { $p } else { $l } }
function Greeting {
    $h = (Get-Date).Hour
    if ($h -ge 5 -and $h -lt 12) { T 'greet_morning' } elseif ($h -ge 12 -and $h -lt 17) { T 'greet_day' }
    elseif ($h -ge 17 -and $h -lt 23) { T 'greet_evening' } else { T 'greet_night' }
}

# ═════════════════════════ Claude Code ═════════════════════════
$ClaudeExe = $null; $ClaudeVersion = ''
function Find-Claude {
    $script:ClaudeExe = $null
    $cands = @(
        (Get-Command claude.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:APPDATA 'npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe'),
        (Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    )
    foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p)) { $script:ClaudeExe = $p; break } }
    $script:ClaudeVersion = Get-ClaudeVersion
}
function Get-ClaudeVersion {
    if (-not $ClaudeExe) { return '' }
    try {
        $pkg = Join-Path (Split-Path (Split-Path $ClaudeExe)) 'package.json'
        if (Test-Path -LiteralPath $pkg) { return [string](Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json).version }
        $stamp = [string](Get-Item -LiteralPath $ClaudeExe).LastWriteTimeUtc.Ticks
        if ($Cfg.verExe -eq $ClaudeExe -and $Cfg.verStamp -eq $stamp -and $Cfg.version) { return [string]$Cfg.version }
        $out = (& $ClaudeExe --version 2>$null | Out-String)
        if ($out -match '(\d+\.\d+\.\d+)') {
            $Cfg.verExe = $ClaudeExe; $Cfg.verStamp = $stamp; $Cfg.version = $Matches[1]; Save-Settings
            return $Matches[1]
        }
    } catch {}
    ''
}
function Get-ClaudeIcon {
    if ($ClaudeExe -and $ClaudeExe.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { return $ClaudeExe }
    $null
}
function Get-RepairFile {
    foreach ($d in @($AppDir, $PSScriptRoot)) {
        if ($d) { $f = Join-Path $d 'REPAIR.md'; if (Test-Path -LiteralPath $f) { return $f } }
    }
    $null
}
function Get-ModDir([string]$name) {
    foreach ($d in @((Join-Path $AppDir $name), (Join-Path $PSScriptRoot $name))) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d '.claude-plugin\plugin.json'))) { return $d }
    }
    $null
}
# Сессия, созданная вместе с собственным модом (~/.claude/dev-mods/<id>/<имя>), уже загружает его сама:
# второй экземпляр не подключаем, чтобы не было двух одинаковых строк.
function Test-DevMod([string]$sessionId, [string]$name) {
    if (-not $sessionId) { return $false }
    Test-Path -LiteralPath (Join-Path $env:USERPROFILE ".claude\dev-mods\$sessionId\$name")
}
function Get-LaunchArgs([string]$sessionId) {
    $a = @()
    if ($Cfg.showLimits) { $mod = Get-ModDir $ModName; if ($mod) { $a += @('--plugin-dir', $mod) } }
    if ($Cfg.limitsBar -and -not (Test-DevMod $sessionId 'limits-status')) {
        $mod = Get-ModDir $BarModName; if ($mod) { $a += @('--plugin-dir', $mod) }
    }
    # свои моды (settings.json → extraPlugins): папки плагинов Claude Code
    foreach ($xp in @($Cfg.extraPlugins)) {
        $xp = [Environment]::ExpandEnvironmentVariables([string]$xp)
        if ($xp -and (Test-Path -LiteralPath (Join-Path $xp '.claude-plugin\plugin.json'))) { $a += @('--plugin-dir', $xp) }
    }
    if ($Cfg.model -and $Cfg.model -ne 'default') { $a += @('--model', [string]$Cfg.model) }
    if ($Cfg.permissionMode -and $Cfg.permissionMode -ne 'default') { $a += @('--permission-mode', [string]$Cfg.permissionMode) }
    $a
}

# ═════════════════════════ история сессий ═════════════════════════
function Open-Reader([string]$file) {
    $fs = New-Object IO.FileStream($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
}
function Get-SessionCwd([string]$file) {
    $sr = $null
    try {
        $sr = Open-Reader $file
        for ($i = 0; $i -lt 40 -and -not $sr.EndOfStream; $i++) {
            $line = $sr.ReadLine()
            if ($line -match '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"') { return ('"' + $Matches[1] + '"' | ConvertFrom-Json) }
        }
    } catch {} finally { if ($sr) { $sr.Dispose() } }
    $null
}
$TitleCache = @{}
function Get-SessionTitle([IO.FileInfo]$f) {
    $ck = $f.FullName + '|' + $f.LastWriteTimeUtc.Ticks
    if ($TitleCache.ContainsKey($ck)) { return $TitleCache[$ck] }
    $title = $null; $sr = $null
    try {
        $sr = Open-Reader $f.FullName
        for ($i = 0; $i -lt 300 -and -not $sr.EndOfStream -and -not $title; $i++) {
            $line = $sr.ReadLine()
            if ($line.Length -gt 300000) { continue }
            if ($line -match '"type"\s*:\s*"summary"') {
                try { $o = $line | ConvertFrom-Json; if ($o.summary) { $title = [string]$o.summary } } catch {}
                continue
            }
            if ($line -notmatch '"type"\s*:\s*"user"') { continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.isMeta -or $o.isSidechain -or -not $o.message) { continue }
            $c = $o.message.content
            $texts = if ($c -is [string]) { @($c) } else { @($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) }
            foreach ($t in $texts) {
                if ($t -and $t.TrimStart() -notmatch '^(<|\[Request interrupted|Caveat:)') { $title = $t; break }
            }
        }
    } catch {} finally { if ($sr) { $sr.Dispose() } }
    if ($title) { $title = ($title -replace '\s+', ' ').Trim() }
    $TitleCache[$ck] = $title
    $title
}
function Get-ClaudeFolders {
    $root = Join-Path $env:USERPROFILE '.claude\projects'
    $map = @{}
    if (Test-Path -LiteralPath $root) {
        foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -Filter *.jsonl -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
            if ($files.Count -eq 0) { continue }
            $cwd = $null
            foreach ($f in ($files | Select-Object -First 5)) { $cwd = Get-SessionCwd $f.FullName; if ($cwd) { break } }
            if (-not $cwd -or -not (Test-Path -LiteralPath $cwd -PathType Container)) { continue }
            $path = Normalize-Path $cwd
            $key = $path.ToLowerInvariant()
            if ($map.ContainsKey($key)) {
                $map[$key].Sessions += $files.Count
                $map[$key].Dirs += $dir.FullName
                if ($files[0].LastWriteTime -gt $map[$key].Last) { $map[$key].Last = $files[0].LastWriteTime }
            } else {
                $map[$key] = [pscustomobject]@{ Path = $path; Sessions = $files.Count; Last = $files[0].LastWriteTime; Dirs = @($dir.FullName) }
            }
        }
    }
    @($map.Values | Sort-Object Last -Descending)
}
function Get-FolderSessions($info, [int]$max) {
    if (-not $info) { return @() }
    $files = @(foreach ($d in $info.Dirs) { Get-ChildItem -LiteralPath $d -Filter *.jsonl -File -ErrorAction SilentlyContinue })
    $out = @()
    foreach ($f in ($files | Sort-Object LastWriteTime -Descending)) {
        $t = Get-SessionTitle $f
        if (-not $t) { continue }
        $out += [pscustomobject]@{ Id = $f.BaseName; Title = $t; Last = $f.LastWriteTime }
        if ($out.Count -ge $max) { break }
    }
    $out
}

# ═════════════════════════ интерфейс ═════════════════════════
function MkItem {
    param([string]$Label, [string]$Sub = '', [string]$Meta = '', [string]$Icon = ' ', [string]$Hot = '', [hashtable]$Data = @{})
    $o = [pscustomobject]@{ Label = $Label; Sub = $Sub; Meta = $Meta; Icon = $Icon; Hot = $Hot }
    foreach ($k in $Data.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $Data[$k] }
    $o
}
function MkSection([string]$Title, [object[]]$Items, [string]$Note = '') {
    [pscustomobject]@{ Title = $Title; Items = @($Items | Where-Object { $_ }); Note = $Note }
}
function ItemRows($it, [bool]$on, [int]$W) {
    $meta = [string]$it.Meta
    $room = $W - 9 - $meta.Length
    if ($room -lt 14) { $meta = ''; $room = $W - 9 }
    $label = FitEnd $it.Label $room
    $gap = ' ' * [math]::Max(1, $W - 7 - $label.Length - $meta.Length)
    $icon = if ($it.Icon) { $it.Icon.Substring(0, 1) } else { ' ' }
    $rows = @()
    if ($on) { $rows += "  $Clay$($G.Bar)$R$SelBg $Clay$icon $Ivory$Bold$label$NoBold$gap$Muted$meta $R" }
    else     { $rows += "    $Dim$icon $Text2$label$gap$Dim$meta $R" }
    if ($it.Sub) {
        $sub = FitEnd $it.Sub ($W - 7)
        $pad = ' ' * [math]::Max(0, $W - 7 - $sub.Length)
        if ($on) { $rows += "  $Clay$($G.Bar)$R$SelBg   $Muted$sub$pad $R" }
        else     { $rows += "      $Dim$sub$R" }
    }
    $rows
}
function Box([string[]]$content, [int]$W) {
    $inner = $W - 8
    $out = @("  $Frame$($G.TL)$($G.Hz * ($W - 4))$($G.TR)$R")
    foreach ($c in $content) { $out += "  $Frame$($G.Vt)$R  " + (PadTo $c $inner) + "$R  $Frame$($G.Vt)$R" }
    $out += "  $Frame$($G.BL)$($G.Hz * ($W - 4))$($G.BR)$R"
    $out
}
function Brand([int]$W, [string]$title = 'Claude Code') {
    $v = if ($ClaudeVersion) { "v$ClaudeVersion" } else { '' }
    Spread "$Clay$($G.Star)$R  $Bold$Ivory$title$R" "$Dim$v$R" ($W - 8)
}

# ───────── лимиты Claude (файл пишет мод usage-mod) ─────────
# Кроме usage.json можно указать другие файлы того же формата (settings.json → extraUsageFiles):
# берётся самый свежий по updatedAt.
function Read-Usage {
    $best = $null; $bestT = [datetime]::MinValue
    foreach ($uf in (@($UsageFile) + @($Cfg.extraUsageFiles))) {
        if (-not $uf) { continue }
        $uf = [Environment]::ExpandEnvironmentVariables([string]$uf)
        if (-not (Test-Path -LiteralPath $uf)) { continue }
        try {
            $u = Get-Content -LiteralPath $uf -Raw -Encoding UTF8 | ConvertFrom-Json
            $ut = [datetime]::MinValue
            if ($u.updatedAt) { try { $ut = [DateTimeOffset]::Parse([string]$u.updatedAt, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } catch {} }
            if (-not $best -or $ut -gt $bestT) { $best = $u; $bestT = $ut }
        } catch {}
    }
    $best
}
function Get-Limits($u) {
    $now = [DateTimeOffset]::Now
    foreach ($l in @($u.limits)) {
        if (-not $l) { continue }
        $pct = [double]$l.percentUsed; $reset = $null; $passed = $false
        if ($l.resetsAt) {
            try {
                $reset = [DateTimeOffset]::Parse([string]$l.resetsAt, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
                if ($reset -lt $now.LocalDateTime) { $pct = 0; $passed = $true }
            } catch {}
        }
        $name = switch ($l.kind) { 'five_hour' { T 'lim_5h' } 'seven_day' { T 'lim_week' } 'spend_limit' { T 'lim_spend' } default { [string]$l.kind } }
        $short = switch ($l.kind) { 'five_hour' { T 'lim_short_5h' } 'seven_day' { T 'lim_short_week' } default { $name } }
        [pscustomobject]@{ Name = $name; Short = $short; Pct = $pct; Reset = $reset; Passed = $passed }
    }
}
function Format-Reset([datetime]$t) {
    $ci = [Globalization.CultureInfo]::GetCultureInfo($(if ($Cfg.lang -eq 'ru') { 'ru-RU' } else { 'en-US' }))
    $today = (Get-Date).Date
    if ($t.Date -eq $today) { return $t.ToString('HH:mm') }
    if ($t.Date -eq $today.AddDays(1)) { return "$(T 'lim_tomorrow') $($t.ToString('HH:mm'))" }
    $t.ToString('ddd HH:mm', $ci)
}
function Pct-Color([double]$p) { if ($p -ge 90) { $Red } elseif ($p -ge 75) { $Amber } else { $Clay } }
# Строки для шапки главного экрана: полоска на каждое окно + модель и свежесть.
function Usage-Lines([int]$W, [switch]$Always) {
    if (-not $Cfg.showLimits -and -not $Always) { return @() }
    $u = Read-Usage
    if (-not $u) { return @('', "   $Dim$(FitEnd (T 'lim_wait') ($W - 12))$R") }
    $lims = @(Get-Limits $u)
    if ($lims.Count -eq 0) { return @('', "   $Dim$(FitEnd (T 'lim_none') ($W - 12))$R") }
    $barW = [math]::Max(10, [math]::Min(28, $W - 62))
    $out = @('')
    foreach ($l in $lims) {
        $fill = [int][math]::Round([math]::Min(100, [math]::Max(0, $l.Pct)) / 100 * $barW)
        $bar = "$(Pct-Color $l.Pct)$($G.BarFull * $fill)$Rule$($G.BarEmpty * ($barW - $fill))$R"
        $when = if ($l.Passed) { T 'lim_reset_done' } elseif ($l.Reset) { TF 'lim_reset' (Format-Reset $l.Reset) } else { '' }
        $out += "   $Text2$($l.Name.PadRight(8))$R  $bar  $Bold$Ivory$('{0,3:0}%' -f $l.Pct)$R  $Dim$when$R"
    }
    $meta = @()
    if ($u.modelName) { $meta += [string]$u.modelName }
    if ($u.updatedAt) { try { $meta += TF 'lim_updated' (Format-Ago ([DateTimeOffset]::Parse([string]$u.updatedAt, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime)) } catch {} }
    if ($meta.Count) { $out += "   $Dim$($meta -join "  $($G.Dot)  ")$R" }
    $out
}
# Одна строка для экрана проекта: «5 ч 43%  ·  неделя 41%».
function Usage-Compact {
    if (-not $Cfg.showLimits) { return '' }
    $u = Read-Usage; if (-not $u) { return '' }
    $parts = @(Get-Limits $u | ForEach-Object { "$Text2$($_.Short) $(Pct-Color $_.Pct)$('{0:0}%' -f $_.Pct)$R" })
    $parts -join "  $Dim$($G.Dot)$R  "
}
# То же без цвета: для поля Meta пунктов меню.
function Usage-Plain {
    $u = Read-Usage; if (-not $u) { return '' }
    (@(Get-Limits $u | ForEach-Object { "$($_.Short) $('{0:0}%' -f $_.Pct)" })) -join " $($G.Dot) "
}
function Hints([object[]]$pairs) {
    '  ' + (($pairs | ForEach-Object { "$Text2$($_[0])$R $Dim$($_[1])$R" }) -join '   ')
}
function Paint([string[]]$lines, [int]$H) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$E[H")
    $n = [math]::Min($lines.Count, $H)
    for ($i = 0; $i -lt $n; $i++) {
        if ($i) { [void]$sb.Append("`n") }
        [void]$sb.Append($lines[$i]); [void]$sb.Append("$R$E[K")
    }
    [void]$sb.Append("$E[J")
    [Console]::Write($sb.ToString())
}
function Console-Width { try { [Console]::WindowWidth } catch { 100 } }
function Get-Width { [math]::Max(44, [math]::Min((Console-Width) - 1, 96)) }
function Window-Top { try { [Console]::WindowTop } catch { 0 } }

# ───────── мышь: чтение ввода консоли напрямую (ReadConsoleInput) ─────────
# Пока открыто меню, консоль присылает события мыши: щелчок по пункту открывает его, колесо листает.
# Перед запуском Claude и при выходе режим консоли возвращается как был (Input-Restore).
# Сборка компилируется один раз и кэшируется в %LOCALAPPDATA%\ClaudeCodeLauncher\bin.
$NativeSrc = @'
using System;
using System.Runtime.InteropServices;
namespace CCL {
  public class ConEvent { public int Kind; public ConsoleKeyInfo Key; public int X; public int Y; public int Delta; }
  public static class ConIn {
    [StructLayout(LayoutKind.Explicit)]
    struct INPUT_RECORD {
      [FieldOffset(0)]  public ushort EventType;
      [FieldOffset(4)]  public int KeyDown;
      [FieldOffset(8)]  public ushort RepeatCount;
      [FieldOffset(10)] public ushort VirtualKeyCode;
      [FieldOffset(12)] public ushort VirtualScanCode;
      [FieldOffset(14)] public ushort UnicodeChar;
      [FieldOffset(16)] public uint KeyControlState;
      [FieldOffset(4)]  public short MouseX;
      [FieldOffset(6)]  public short MouseY;
      [FieldOffset(8)]  public uint ButtonState;
      [FieldOffset(12)] public uint MouseControlState;
      [FieldOffset(16)] public uint EventFlags;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint n);
    [DllImport("kernel32.dll", EntryPoint = "ReadConsoleInputW")] static extern bool ReadConsoleInput(IntPtr h, [Out] INPUT_RECORD[] buf, uint len, out uint read);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    static IntPtr hIn = IntPtr.Zero;
    static uint saved;
    static bool active;
    static uint buttons;
    static int lastX = -1, lastY = -1, lastPress = 0;
    public static bool Active { get { return active; } }
    public static bool Enable() {
      hIn = GetStdHandle(-10);
      uint m;
      if (!GetConsoleMode(hIn, out m)) return false;
      if (!active) saved = m;
      // + ENABLE_WINDOW_INPUT, ENABLE_MOUSE_INPUT, ENABLE_EXTENDED_FLAGS; - QUICK_EDIT, VIRTUAL_TERMINAL_INPUT
      uint nm = (m | 0x0008u | 0x0010u | 0x0080u) & ~0x0040u & ~0x0200u;
      if (!SetConsoleMode(hIn, nm)) return false;
      active = true;
      return true;
    }
    public static void Restore() {
      if (!active) return;
      SetConsoleMode(hIn, saved);
      active = false;
    }
    static bool IsModifier(ushort vk) {
      return vk == 0x10 || vk == 0x11 || vk == 0x12 || vk == 0x14 || vk == 0x90 || vk == 0x91 || vk == 0x5B || vk == 0x5C || (vk >= 0xA0 && vk <= 0xA5);
    }
    // Kind: 0 ничего, 1 клавиша, 2 щелчок левой кнопкой, 3 колесо, 4 движение, 5 размер окна
    public static ConEvent Read(int timeoutMs) {
      ConEvent ev = new ConEvent();
      if (WaitForSingleObject(hIn, (uint)timeoutMs) != 0) return ev;
      uint n;
      if (!GetNumberOfConsoleInputEvents(hIn, out n) || n == 0) return ev;
      INPUT_RECORD[] buf = new INPUT_RECORD[1];
      uint read;
      if (!ReadConsoleInput(hIn, buf, 1, out read) || read == 0) return ev;
      INPUT_RECORD r = buf[0];
      if (r.EventType == 1) {
        if (r.KeyDown == 0 || IsModifier(r.VirtualKeyCode)) return ev;
        uint cs = r.KeyControlState;
        ev.Kind = 1;
        ev.Key = new ConsoleKeyInfo((char)r.UnicodeChar, (ConsoleKey)r.VirtualKeyCode, (cs & 0x10) != 0, (cs & 0x03) != 0, (cs & 0x0C) != 0);
      } else if (r.EventType == 2) {
        ev.X = r.MouseX; ev.Y = r.MouseY;
        uint fl = r.EventFlags;
        if (fl == 4) {
          short d = (short)(r.ButtonState >> 16);
          ev.Kind = 3; ev.Delta = d > 0 ? 1 : -1;
        } else if (fl == 0) {
          uint prev = buttons; buttons = r.ButtonState;
          if ((r.ButtonState & 1u) != 0 && (prev & 1u) == 0) {
            int now = Environment.TickCount;
            // второй щелчок двойного щелчка не должен нажать пункт на следующем экране
            if (unchecked(now - lastPress) > 350) ev.Kind = 2;
            lastPress = now;
          }
        } else if (fl == 2) {
          buttons = r.ButtonState; lastPress = Environment.TickCount;
        } else if (fl == 1) {
          buttons = r.ButtonState;
          if (ev.X != lastX || ev.Y != lastY) { lastX = ev.X; lastY = ev.Y; ev.Kind = 4; }
        }
      } else if (r.EventType == 4) {
        ev.Kind = 5;
      }
      return ev;
    }
  }
}
'@
$Native = $false
function Init-Native {
    if ($Native) { return }
    try { if ([Console]::IsInputRedirected) { return } } catch { return }
    if (-not ('CCL.ConIn' -as [type])) {
        try {
            $sha = [Security.Cryptography.SHA1]::Create()
            $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($NativeSrc))) -replace '-', '').Substring(0, 12)
            $dll = Join-Path $AppDir "bin\ccl-input-$hash.dll"
            if (-not (Test-Path -LiteralPath $dll)) {
                New-Item -ItemType Directory -Force -Path (Split-Path $dll) | Out-Null
                Add-Type -TypeDefinition $NativeSrc -OutputAssembly $dll -OutputType Library
            }
            if (-not ('CCL.ConIn' -as [type])) { Add-Type -LiteralPath $dll }
        } catch {
            try { if (-not ('CCL.ConIn' -as [type])) { Add-Type -TypeDefinition $NativeSrc } } catch {}
        }
    }
    if ('CCL.ConIn' -as [type]) {
        try { if ([CCL.ConIn]::Enable()) { [CCL.ConIn]::Restore(); $script:Native = $true } } catch {}
    }
}
function Input-Restore { if ($Native) { try { [CCL.ConIn]::Restore() } catch {} } }

# Экран: шапка + секции + подсказки. Возвращает @{Item; Action; Index} или $null (Esc).
function Run-Screen {
    param([scriptblock]$Header, [scriptblock]$Sections, [object[]]$Keys, [switch]$Search,
          [int]$Start = 0, [switch]$AllowDelete, [switch]$AllowLR)
    $sel = $Start; $scroll = 0; $query = ''; $lastSize = ''
    [Console]::CursorVisible = $false
    while ($true) {
        $ww = [Console]::WindowWidth; $H = [Console]::WindowHeight
        $W = Get-Width
        $size = "${ww}x$H"
        if ($size -ne $lastSize) { Clear-Screen; $lastSize = $size }

        $secs = @(& $Sections $query)
        $list = @(foreach ($s in $secs) { $s.Items })
        $n = $list.Count
        if ($sel -ge $n) { $sel = [math]::Max(0, $n - 1) }
        if ($sel -lt 0) { $sel = 0 }

        $top = @('') + @(& $Header $W)
        if ($Search) {
            $top += ''
            if ($query) { $top += "  $Clay/$R $Ivory$query$Clay$($G.Caret)$R" }
            else        { $top += "  $Dim$(T 'search_hint')$R" }
        }
        $top += ''

        $rows = New-Object Collections.Generic.List[object]
        $idx = 0
        foreach ($s in $secs) {
            if ($s.Items.Count -eq 0) { continue }
            if ($rows.Count) { $rows.Add(@('', -1)) }
            if ($s.Title) {
                $rows.Add(@((Spread "  $Muted$Bold$($s.Title)$R" "$Dim$($s.Note) $R" $W), -1))
                $rows.Add(@("  $Rule$($G.Hz * ($W - 2))$R", -1))
            }
            foreach ($it in $s.Items) {
                foreach ($t in (ItemRows $it ($idx -eq $sel) $W)) { $rows.Add(@($t, $idx)) }
                $idx++
            }
        }
        if ($n -eq 0) { $rows.Add(@("    $Muted$(T 'nothing')$R", -1)) }

        $foot = @('', (Hints $Keys))
        $avail = [math]::Max(3, $H - $top.Count - $foot.Count)
        $view = @(); $viewIdx = @()
        if ($rows.Count -le $avail) {
            $view = @($rows | ForEach-Object { $_[0] }); $viewIdx = @($rows | ForEach-Object { $_[1] }); $scroll = 0
        } else {
            $fRow = -1; $lRow = -1
            for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i][1] -eq $sel) { if ($fRow -lt 0) { $fRow = $i }; $lRow = $i } }
            if ($lRow + 2 -gt $scroll + $avail) { $scroll = $lRow + 2 - $avail }
            if ($fRow - 1 -lt $scroll) { $scroll = [math]::Max(0, $fRow - 3) }
            $scroll = [math]::Max(0, [math]::Min($scroll, $rows.Count - $avail))
            for ($i = $scroll; $i -lt $scroll + $avail; $i++) { $view += $rows[$i][0]; $viewIdx += $rows[$i][1] }
            if ($scroll -gt 0) { $view[0] = "  $Dim$($G.Up)$R"; $viewIdx[0] = -2 }
            if ($scroll + $avail -lt $rows.Count) { $view[$view.Count - 1] = "  $Dim$($G.Down)$R"; $viewIdx[$viewIdx.Count - 1] = -3 }
        }
        $filler = @(for ($i = $view.Count; $i -lt $avail; $i++) { '' })
        Paint (@($top) + @($view) + $filler + $foot) $H
        # строка экрана -> номер пункта (для мыши); -1 не пункт, -2/-3 стрелки прокрутки
        $rowMap = @(@($top | ForEach-Object { -1 }) + $viewIdx)

        $res = { param($a) [pscustomobject]@{ Item = $list[$sel]; Action = $a; Index = $sel } }
        $k = $null
        if ($Native) {
            [void][CCL.ConIn]::Enable()
            while ($true) {
                $ev = [CCL.ConIn]::Read(40)
                if ($ev.Kind -eq 1) { $k = $ev.Key; break }
                if ($ev.Kind -eq 5) { break }
                if ($ev.Kind -ge 2 -and $ev.Kind -le 4) {
                    $mRow = $ev.Y - (Window-Top)
                    $hit = if ($mRow -ge 0 -and $mRow -lt $rowMap.Count) { [int]$rowMap[$mRow] } else { -1 }
                    if ($ev.Kind -eq 2) {
                        if ($hit -ge 0 -and $hit -lt $n) { $sel = $hit; return (& $res 'enter') }
                        if ($hit -eq -2 -and $n) { $sel = [math]::Max(0, $sel - 3); break }
                        if ($hit -eq -3 -and $n) { $sel = [math]::Min($n - 1, $sel + 3); break }
                        continue
                    }
                    if ($ev.Kind -eq 3) {
                        if ($n) { if ($ev.Delta -gt 0) { $sel = [math]::Max(0, $sel - 1) } else { $sel = [math]::Min($n - 1, $sel + 1) } }
                        break
                    }
                    if ($hit -ge 0 -and $hit -lt $n -and $hit -ne $sel) { $sel = $hit; break }
                    continue
                }
                if ("$([Console]::WindowWidth)x$([Console]::WindowHeight)" -ne $lastSize) { break }
                if (Poll-Background) { break }
            }
        } else {
            while (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 40
                if ("$([Console]::WindowWidth)x$([Console]::WindowHeight)" -ne $lastSize) { break }
                if (Poll-Background) { break }
            }
            if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true) }
        }
        if (-not $k) { continue }
        $key = $k.Key
        $ctrl = [bool]($k.Modifiers -band [ConsoleModifiers]::Control)
        $shift = [bool]($k.Modifiers -band [ConsoleModifiers]::Shift)

        if ($key -eq [ConsoleKey]::UpArrow -or ($key -eq [ConsoleKey]::Tab -and $shift)) { if ($n) { $sel = ($sel - 1 + $n) % $n } }
        elseif ($key -eq [ConsoleKey]::DownArrow -or $key -eq [ConsoleKey]::Tab) { if ($n) { $sel = ($sel + 1) % $n } }
        elseif ($key -eq [ConsoleKey]::PageUp) { $sel = [math]::Max(0, $sel - 5) }
        elseif ($key -eq [ConsoleKey]::PageDown) { $sel = [math]::Min([math]::Max(0, $n - 1), $sel + 5) }
        elseif ($key -eq [ConsoleKey]::Home -and -not $query) { $sel = 0 }
        elseif ($key -eq [ConsoleKey]::End -and -not $query) { $sel = [math]::Max(0, $n - 1) }
        elseif ($key -eq [ConsoleKey]::Enter) { if ($n) { return (& $res 'enter') } }
        elseif ($AllowLR -and $key -eq [ConsoleKey]::LeftArrow) { if ($n) { return (& $res 'left') } }
        elseif ($AllowLR -and $key -eq [ConsoleKey]::RightArrow) { if ($n) { return (& $res 'right') } }
        elseif ($AllowDelete -and $key -eq [ConsoleKey]::Delete) { if ($n) { return (& $res 'delete') } }
        elseif ($key -eq [ConsoleKey]::Escape) { if ($query) { $query = ''; $sel = 0 } else { return $null } }
        elseif ($key -eq [ConsoleKey]::Backspace) { if ($query) { $query = $query.Substring(0, $query.Length - 1); $sel = 0 } }
        elseif ($Search -and -not $ctrl -and $k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $query += $k.KeyChar; $sel = 0 }
        elseif (-not $Search -and -not $ctrl) {
            for ($i = 0; $i -lt $n; $i++) {
                if ($list[$i].Hot -and $list[$i].Hot -eq $key.ToString()) { $sel = $i; return (& $res 'enter') }
            }
        }
    }
}

# ═════════════════════════ выбор папки ═════════════════════════
function Select-FolderDialog([string]$initial) {
    try {
        if (-not ('CCL.FolderPicker' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CCL {
  [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IShellItem {
    void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
    void GetParent(out IShellItem ppsi);
    void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
    void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
    void Compare(IShellItem psi, uint hint, out int piOrder);
  }
  [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IFileDialog {
    [PreserveSig] int Show(IntPtr parent);
    void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
    void SetFileTypeIndex(uint iFileType);
    void GetFileTypeIndex(out uint piFileType);
    void Advise(IntPtr pfde, out uint pdwCookie);
    void Unadvise(uint dwCookie);
    void SetOptions(uint fos);
    void GetOptions(out uint pfos);
    void SetDefaultFolder(IShellItem psi);
    void SetFolder(IShellItem psi);
    void GetFolder(out IShellItem ppsi);
    void GetCurrentSelection(out IShellItem ppsi);
    void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
    void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
    void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
    void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
    void GetResult(out IShellItem ppsi);
  }
  [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
  public class FileOpenDialogCoClass { }
  public static class FolderPicker {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem ppv);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    public static string Pick(string title, string okLabel, string initial) {
      IFileDialog dlg = (IFileDialog)new FileOpenDialogCoClass();
      uint opts; dlg.GetOptions(out opts);
      dlg.SetOptions(opts | 0x20 | 0x40);
      dlg.SetTitle(title);
      dlg.SetOkButtonLabel(okLabel);
      if (!string.IsNullOrEmpty(initial)) {
        try { IShellItem f; SHCreateItemFromParsingName(initial, IntPtr.Zero, typeof(IShellItem).GUID, out f); dlg.SetFolder(f); } catch { }
      }
      if (dlg.Show(GetForegroundWindow()) != 0) return null;
      IShellItem res; dlg.GetResult(out res);
      string path; res.GetDisplayName(0x80058000, out path);
      return path;
    }
  }
}
'@
        }
        return [CCL.FolderPicker]::Pick((T 'pick_title'), (T 'pick_ok'), $initial)
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = (T 'pick_title'); $dlg.SelectedPath = $initial
        try { if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath } } finally { $dlg.Dispose() }
    }
    $null
}

# ═════════════════════════ установка / удаление ═════════════════════════
function Get-WindowGeometry {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        if (-not ('CCL.Dpi' -as [type])) {
            Add-Type -Namespace CCL -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
        }
        [void][CCL.Dpi]::SetProcessDPIAware()
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $scale = $g.DpiX / 96; $g.Dispose()
        $rows = [int][math]::Max(24, [math]::Min(40, [math]::Floor(($wa.Height / $scale - 110) / 18.4)))
        $cols = [int][math]::Max(70, [math]::Min(100, [math]::Floor(($wa.Width / $scale - 140) / 9.6)))
        $winW = ($cols * 9.6 + 60) * $scale; $winH = ($rows * 18.4 + 64) * $scale
        @{ Cols = $cols; Rows = $rows
           X = [int]($wa.X + [math]::Max(0, ($wa.Width - $winW) / 2))
           Y = [int]($wa.Y + [math]::Max(0, ($wa.Height - $winH) / 2)) }
    } catch { @{ Cols = 100; Rows = 34; X = 100; Y = 40 } }
}
function Get-ShortcutPaths {
    @((Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName),
      (Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName))
}
function Write-Fragment {
    $prof = [ordered]@{
        name = $ProfileName
        commandline = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$AppScript`""
        startingDirectory = '%USERPROFILE%'; tabTitle = 'Claude Code'; suppressApplicationTitle = $true
        tabColor = '#D97757'; colorScheme = $SchemeName
        font = [ordered]@{ face = 'Cascadia Mono'; size = 12 }
        padding = '18, 14'; cursorShape = 'bar'; useAcrylic = $false; closeOnExit = 'always'
    }
    $icon = Get-ClaudeIcon; if ($icon) { $prof.icon = $icon }
    $scheme = [ordered]@{
        name = $SchemeName; background = '#262624'; foreground = '#F0EEE6'; cursorColor = '#D97757'; selectionBackground = '#4A3F38'
        black = '#1F1E1D'; red = '#E06C5A'; green = '#8FB573'; yellow = '#E8B964'; blue = '#7AA2D6'; purple = '#B48EC8'; cyan = '#6FB8B0'; white = '#D6D3C8'
        brightBlack = '#6E6B64'; brightRed = '#F08A78'; brightGreen = '#A8C98E'; brightYellow = '#F2CE85'; brightBlue = '#9BBCE6'
        brightPurple = '#CBA9DB'; brightCyan = '#8FCFC7'; brightWhite = '#FAF9F5'
    }
    New-Item -ItemType Directory -Force -Path $FragmentDir | Out-Null
    $json = [ordered]@{ profiles = @($prof); schemes = @($scheme) } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $FragmentDir 'launcher.json'), $json, (New-Object Text.UTF8Encoding $false))
}
function Write-Shortcuts {
    $geo = Get-WindowGeometry
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $shell = New-Object -ComObject WScript.Shell
    foreach ($lnk in Get-ShortcutPaths) {
        $dir = Split-Path $lnk
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $s = $shell.CreateShortcut($lnk)
        if ($wt) {
            $s.TargetPath = $wt.Source
            $s.Arguments = "--size $($geo.Cols),$($geo.Rows) --pos $($geo.X),$($geo.Y) -p `"$ProfileName`""
        } else {
            $s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $s.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$AppScript`""
        }
        $s.WorkingDirectory = $env:USERPROFILE
        $icon = Get-ClaudeIcon; if ($icon) { $s.IconLocation = "$icon,0" }
        $s.Description = $AppName
        $s.Save()
    }
}
function Write-Step([string]$state, [string]$text, [string]$note = '') {
    $mark = switch ($state) { 'ok' { "$Green$($G.Ok)" } 'warn' { "$Amber!" } default { "$Red$($G.Err)" } }
    $line = "    $mark$R  $Ivory$text$R"
    if ($note) { $line += "  $Dim$note$R" }
    [Console]::WriteLine($line)
}
function Invoke-Install {
    $W = [math]::Max(44, [math]::Min((Console-Width) - 1, 80))
    Clear-Screen
    [Console]::WriteLine('')
    (Box @('', (Brand $W $AppName), "   $Muted$(T 'i_title')$R", '') $W) | ForEach-Object { [Console]::WriteLine($_) }
    [Console]::WriteLine('')

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) { Write-Step 'ok' (T 'i_wt') } else { Write-Step 'warn' (T 'i_wt') (T 'i_wt_missing') }
    if ($ClaudeExe) { Write-Step 'ok' (T 'i_claude') $(if ($ClaudeVersion) { "v$ClaudeVersion" }) }
    else { Write-Step 'warn' (T 'i_claude') (T 'i_claude_missing') }
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { Write-Step 'ok' (T 'i_git') }
    else { Write-Step 'warn' (T 'i_git') "$(T 'i_git_missing'): $GitUrl" }
    [Console]::WriteLine('')

    try {
        New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
        if ($PSCommandPath -and ((Resolve-Path -LiteralPath $PSCommandPath).Path -ne $AppScript)) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $AppScript -Force
            foreach ($mn in @($ModName, $BarModName)) {
                $srcMod = Join-Path $PSScriptRoot $mn
                if (Test-Path -LiteralPath $srcMod) {
                    $dstMod = Join-Path $AppDir $mn
                    if (Test-Path -LiteralPath $dstMod) { Remove-Item -LiteralPath $dstMod -Recurse -Force }
                    Copy-Item -LiteralPath $srcMod -Destination $dstMod -Recurse -Force
                }
            }
            foreach ($fn in @('REPAIR.md', 'Repair.cmd', 'README.txt', 'POLICY.md', 'POLICY.kk.md', 'POLICY.en.md')) {
                $src = Join-Path $PSScriptRoot $fn
                if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $AppDir $fn) -Force }
            }
        }
        Write-Step 'ok' (T 'i_files') (Format-Path $AppDir)
    } catch { Write-Step 'err' (T 'i_files') $_.Exception.Message; return }
    if ($wt) {
        try { Write-Fragment; Write-Step 'ok' (T 'i_profile') } catch { Write-Step 'err' (T 'i_profile') $_.Exception.Message }
    }
    try { Write-Shortcuts; Write-Step 'ok' (T 'i_shortcuts') } catch { Write-Step 'err' (T 'i_shortcuts') $_.Exception.Message }
    if (-not (Test-Path -LiteralPath $SettingsFile)) { Save-Settings }

    [Console]::WriteLine('')
    [Console]::WriteLine("  $Clay$($G.Star)$R $Ivory$(T 'i_done')$R")
    if ($Quiet) { return }
    [Console]::WriteLine("`n  $Dim$(T 'i_launch')$R")
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq [ConsoleKey]::Enter) { Start-Process -FilePath (Get-ShortcutPaths)[0] }
}
function Remove-LauncherFiles {
    foreach ($lnk in Get-ShortcutPaths) { if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force } }
    if (Test-Path -LiteralPath $FragmentDir) { Remove-Item -LiteralPath $FragmentDir -Recurse -Force }
    if (Test-Path -LiteralPath $AppDir) { Remove-Item -LiteralPath $AppDir -Recurse -Force }
}
function Invoke-Uninstall {
    if (-not $Quiet) {
        Clear-Screen
        [Console]::WriteLine("`n  $Clay$($G.Star)$R $Bold$Ivory$AppName$R  $Dim$($G.Dot) $(T 'u_title')$R`n")
        [Console]::WriteLine("  $Ivory$(T 'u_q')$R")
        $k = [Console]::ReadKey($true)
        if ($k.Key -ne [ConsoleKey]::Y) { [Console]::WriteLine("`n  $Dim$(T 'u_cancel')$R"); return }
    }
    Remove-LauncherFiles
    [Console]::WriteLine("`n  $Green$($G.Ok)$R $Ivory$(T 'u_done')$R")
}

# ═════════════════════════ обновления и каталог скиллов ═════════════════════════
# В корне репозитория лежит manifest.json (его собирает tools\Make-Manifest.ps1):
#   version, date, changelog[{version,date,ru[],en[]}], files[{path,sha256,size}],
#   skills[{name,description,rev,files[{path,sha256,size}]}]
# Источник: 'владелец/репозиторий[@ветка]' (raw.githubusercontent.com), https://…/ или путь к папке.
function Get-Source { $s = [string]$Cfg.updateSource; if (-not $s) { $s = $DefaultSource }; ([string]$s).Trim() }
function Format-Source([string]$s) { if ($s) { $s } else { T 'src_none' } }
$FetchBlock = {
    param([string]$src, [string]$rel, [int]$timeout)
    $ErrorActionPreference = 'Stop'
    if ($src -match '^[a-zA-Z]:[\\/]|^\\\\') { return , [IO.File]::ReadAllBytes((Join-Path $src ($rel -replace '/', '\'))) }
    if ($src -match '^https?://') { $base = $src.TrimEnd('/') + '/' }
    else {
        $repo = $src; $branch = 'main'
        if ($src -match '^(.+?)@(.+)$') { $repo = $Matches[1]; $branch = $Matches[2] }
        $base = "https://raw.githubusercontent.com/$repo/$branch/"
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $url = $base + (($rel -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
    # Сначала curl.exe из Windows: он сам переключается между IPv6 и IPv4. .NET в PowerShell 5.1 зависает
    # до таймаута, если первый IPv6-адрес GitHub недоступен (так бывает у многих провайдеров).
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $curl) {
        $tmp = [IO.Path]::GetTempFileName()
        try {
            $psi = New-Object Diagnostics.ProcessStartInfo $curl
            $psi.Arguments = "-fsSL --max-time $([math]::Ceiling($timeout / 1000)) -A ClaudeCodeLauncher -H `"Cache-Control: no-cache`" -o `"$tmp`" `"$url`""
            $psi.UseShellExecute = $false; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
            $pr = [Diagnostics.Process]::Start($psi)
            $cerr = $pr.StandardError.ReadToEnd(); $pr.WaitForExit()
            if ($pr.ExitCode -eq 0) { return , [IO.File]::ReadAllBytes($tmp) }
            if ($cerr -match 'error: (\d{3})') { throw "The remote server returned an error: ($($Matches[1]))" }
            # прочие ошибки curl (сеть, прокси): пробуем ещё раз через .NET ниже
        } finally { try { [IO.File]::Delete($tmp) } catch {} }
    }
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeout; $req.ReadWriteTimeout = $timeout
    $req.UserAgent = 'ClaudeCodeLauncher'
    $req.Headers.Add('Cache-Control', 'no-cache')
    $resp = $req.GetResponse()
    try {
        $ms = New-Object IO.MemoryStream
        $resp.GetResponseStream().CopyTo($ms)
        return , $ms.ToArray()
    } finally { $resp.Close() }
}
$Upd = [pscustomobject]@{ State = 'idle'; Manifest = $null; Error = ''; Job = $null; Time = $null }
# Понятный текст вместо «Exception calling GetResponse…»
function Friendly-Error([string]$m) {
    $m = $m -replace '^Exception calling "[^"]+" with "\d+" argument\(s\): ', '' -replace '^"|"$', ''
    if ($m -match '\(404\)') { return (TF 'err_404' (Format-Source (Get-Source))) }
    if ($m -match '\(40[13]\)') { return (T 'err_private') }
    if ($m -match 'could not be resolved|Unable to connect|timed out|timeout|разрешить|подключ|время ожидания|SSL|TLS') { return (T 'err_net') }
    if ($m -match "Could not find (a part of the path|file) '([^']+)'") { return (TF 'err_nofile' $Matches[2]) }
    $m
}
function Test-Newer([string]$a, [string]$b) { try { [version]$a -gt [version]$b } catch { $false } }
function Set-UpdateResult([string]$text) {
    if ($text.StartsWith('ERR:')) { $Upd.State = 'error'; $Upd.Error = Friendly-Error $text.Substring(4).Trim(); return }
    try {
        $m = $text.TrimStart([char]0xFEFF) | ConvertFrom-Json
        if (-not $m.version) { throw 'manifest.json: no "version"' }
        $Upd.Manifest = $m; $Upd.Time = Get-Date; $Upd.Error = ''
        $Upd.State = if (Test-Newer ([string]$m.version) $AppVersion) { 'available' } else { 'latest' }
        $Cfg.lastCheck = [DateTimeOffset]::Now.ToString('o'); $Cfg.latestVersion = [string]$m.version; Save-Settings
    } catch { $Upd.State = 'error'; $Upd.Error = $_.Exception.Message }
}
# Тихая проверка в фоне: экран не ждёт сеть, а перерисуется, когда ответ придёт (Poll-Background).
function Start-UpdateCheck {
    if ($Upd.Job) { return }
    $src = Get-Source
    if (-not $src) { $Upd.State = 'nosrc'; return }
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            param($fetch, $src)
            try { [Text.Encoding]::UTF8.GetString([byte[]](& ([scriptblock]::Create($fetch)) $src 'manifest.json' 10000)) }
            catch { 'ERR:' + $_.Exception.Message }
        }.ToString())
        [void]$ps.AddArgument($FetchBlock.ToString()); [void]$ps.AddArgument($src)
        $Upd.Job = @{ PS = $ps; Handle = $ps.BeginInvoke() }
        $Upd.State = 'checking'
    } catch { $Upd.State = 'error'; $Upd.Error = $_.Exception.Message }
}
function Poll-Background {
    $j = $Upd.Job
    if (-not $j -or -not $j.Handle.IsCompleted) { return $false }
    $out = ''
    try { $out = (@($j.PS.EndInvoke($j.Handle)) | ForEach-Object { [string]$_ }) -join '' } catch { $out = 'ERR:' + $_.Exception.Message }
    try { $j.PS.Dispose() } catch {}
    $Upd.Job = $null
    Set-UpdateResult $out
    $true
}
function Wait-UpdateCheck { while ($Upd.Job -and -not $Upd.Job.Handle.IsCompleted) { Start-Sleep -Milliseconds 50 }; [void](Poll-Background) }
function Check-UpdateNow {
    Wait-UpdateCheck
    $src = Get-Source
    if (-not $src) { $Upd.State = 'nosrc'; return }
    try { Set-UpdateResult ([Text.Encoding]::UTF8.GetString([byte[]](& $FetchBlock $src 'manifest.json' 10000))) }
    catch { $Upd.State = 'error'; $Upd.Error = Friendly-Error $_.Exception.Message }
}
function Get-Manifest([switch]$Fresh) {
    Wait-UpdateCheck
    if ($Fresh -or -not $Upd.Manifest -or -not $Upd.Time -or ((Get-Date) - $Upd.Time).TotalMinutes -gt 10) { Check-UpdateNow }
    $Upd.Manifest
}
function Update-Pending { $Upd.State -eq 'available' -and $Upd.Manifest -and [string]$Upd.Manifest.version -ne [string]$Cfg.skipVersion }
function Lang-Text($v) {
    if ($null -eq $v) { return '' }
    if ($v -is [string]) { return $v }
    $t = $v.([string]$Cfg.lang); if (-not $t) { $t = $v.en }; if (-not $t) { $t = $v.ru }
    $t
}
function Wrap-Text([string]$s, [int]$max) {
    $max = [math]::Max(10, $max); $out = @(); $line = ''
    foreach ($wd in ($s -split '\s+' | Where-Object { $_ })) {
        if ($line -and ($line.Length + 1 + $wd.Length) -gt $max) { $out += $line; $line = $wd }
        elseif ($line) { $line += ' ' + $wd } else { $line = $wd }
    }
    if ($line) { $out += $line }
    $out
}
# Строки «Что нового» для всех версий новее текущей.
function Update-Notes($man, [int]$width, [int]$maxLines = 14) {
    $out = @()
    foreach ($c in @($man.changelog | Where-Object { $_ -and (Test-Newer ([string]$_.version) $AppVersion) })) {
        $hd = "   $Text2${Bold}v$($c.version)$NoBold$R"
        if ($c.date) { $hd += "  $Dim$($G.Dot)  $($c.date)$R" }
        $out += $hd
        $items = $c.([string]$Cfg.lang); if (-not $items) { $items = $c.ru }
        foreach ($it in @($items)) {
            $first = $true
            foreach ($ln in (Wrap-Text ([string]$it) ($width - 16))) {
                $mark = if ($first) { "$Clay$($G.Bul)$R" } else { ' ' }
                $out += "     $mark $Ivory$ln$R"; $first = $false
            }
        }
    }
    if ($out.Count -gt $maxLines) { $out = @($out[0..($maxLines - 2)]) + "     $Dim$($G.Ell)$R" }
    $out
}
function Test-SafeRel([string]$p) {
    $p -and $p -notmatch '(^|[\\/])\.\.([\\/]|$)' -and $p -notmatch '^[\\/]' -and $p -notmatch ':'
}
function Get-Sha256([byte[]]$b) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
# Скачивает файлы во временную папку и сверяет контрольные суммы. Ошибка: исключение, на месте ничего не тронуто.
function Download-Files($files, [string]$stage, [scriptblock]$onFile) {
    $src = Get-Source
    $list = @($files)
    foreach ($f in $list) { if (-not (Test-SafeRel ([string]$f.path))) { throw "$(T 'upd_bad_path'): $($f.path)" } }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    # сначала вся пачка одним запуском curl; чего не хватило или не сошлось, докачиваем по одному
    if ($list.Count -gt 1) { try { Fetch-Batch (Get-RawBase $src) @($list | ForEach-Object { [string]$_.path }) $stage } catch {} }
    foreach ($f in $list) {
        $rel = [string]$f.path
        $want = ([string]$f.sha256).ToLowerInvariant()
        $dst = Join-Path $stage ($rel -replace '/', '\')
        $bytes = $null
        if (Test-Path -LiteralPath $dst) { $bytes = [IO.File]::ReadAllBytes($dst) }
        if ($null -eq $bytes -or ($want -and (Get-Sha256 $bytes) -ne $want)) {
            try { $bytes = [byte[]](& $FetchBlock $src $rel 30000) } catch { throw "$($rel): $(Friendly-Error $_.Exception.Message)" }
        }
        if ($want -and (Get-Sha256 $bytes) -ne $want) { throw "$($rel): $(T 'upd_verify_fail')" }
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        [IO.File]::WriteAllBytes($dst, $bytes)
        if ($onFile) { & $onFile $rel }
    }
}
# Адрес, от которого считаются пути файлов; для папки на диске $null.
function Get-RawBase([string]$src) {
    if (-not $src -or $src -match '^[a-zA-Z]:[\\/]|^\\\\') { return $null }
    if ($src -match '^https?://') { return ($src.TrimEnd('/') + '/') }
    $repo = $src; $branch = 'main'
    if ($src -match '^(.+?)@(.+)$') { $repo = $Matches[1]; $branch = $Matches[2] }
    "https://raw.githubusercontent.com/$repo/$branch/"
}
# Много файлов одним запуском curl.exe: соединение не открывается заново на каждый файл.
# Пути относительные, curl работает в папке $stage, поэтому кириллица в пути ему не мешает.
function Fetch-Batch([string]$base, [string[]]$rels, [string]$stage) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not $base -or -not (Test-Path -LiteralPath $curl)) { return }
    for ($i = 0; $i -lt $rels.Count; $i += 40) {
        $part = $rels[$i..([math]::Min($i + 39, $rels.Count - 1))]
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('-fsSL --create-dirs --max-time 300 -A ClaudeCodeLauncher -H "Cache-Control: no-cache"')
        foreach ($rel in $part) {
            $url = $base + (($rel -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
            [void]$sb.Append(" -o `"$($rel -replace '/', '\')`" `"$url`"")
        }
        $psi = New-Object Diagnostics.ProcessStartInfo $curl
        $psi.Arguments = $sb.ToString(); $psi.WorkingDirectory = $stage
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $pr = [Diagnostics.Process]::Start($psi)
        if (-not $pr.WaitForExit(330000)) { try { $pr.Kill() } catch {} }
    }
}
# Временная папка внутри папки лаунчера: %TEMP% бывает в коротком виде (C:\Users\9734~1), на нём Remove-Item падает.
function New-StageDir { Join-Path $AppDir ('tmp\' + [guid]::NewGuid().ToString('N').Substring(0, 10)) }
function Remove-StageDir([string]$d) { try { if ([IO.Directory]::Exists($d)) { [IO.Directory]::Delete($d, $true) } } catch {} }
function Install-Update {
    $man = $Upd.Manifest; $ver = [string]$man.version
    Clear-Screen; Input-Restore
    [Console]::WriteLine("`n  $Clay$($G.Star)$R $Bold$Ivory$(TF 'upd_downloading' $ver)$R`n")
    $target = $PSScriptRoot
    $stage = New-StageDir
    $files = @($man.files | Where-Object { $_ -and $_.path -and ([string]$_.path) -notmatch '^(tools|skills)/' })
    try {
        Download-Files $files $stage { param($rel) Write-Step 'ok' $rel }
        foreach ($f in $files) {
            $rel = ([string]$f.path) -replace '/', '\'
            $dst = Join-Path $target $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item -LiteralPath (Join-Path $stage $rel) -Destination $dst -Force
        }
    } catch {
        Write-Step 'err' $_.Exception.Message
        Wait-AnyKey
        return $false
    } finally {
        Remove-StageDir $stage
    }
    $Cfg.skipVersion = ''; Save-Settings
    [Console]::WriteLine("`n  $Green$($G.Ok)$R $Ivory$(TF 'upd_applied' $ver)$R")
    Start-Sleep -Milliseconds 800
    $true
}
# Перезапуск уже обновлённого скрипта в том же окне.
function Restart-Launcher {
    Input-Restore; Clear-Screen
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'launcher.ps1') -Updated
    exit 0
}

# ───────── скиллы ─────────
function Skill-State($s) {
    $dir = Join-Path $SkillsDir ([string]$s.name)
    if (-not (Test-Path -LiteralPath $dir)) { return 'none' }
    $mine = $Cfg.skills[[string]$s.name]
    if (-not $mine) { return 'local' }
    if ([string]$mine -ne [string]$s.rev) { return 'update' }
    'ok'
}
function Install-Skill($s) {
    $name = [string]$s.name
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "$(T 'upd_bad_path'): $name" }
    $prefix = "skills/$name/"
    $files = @($s.files | Where-Object { $_ })
    foreach ($f in $files) {
        if (-not ([string]$f.path).StartsWith($prefix, [StringComparison]::Ordinal) -or -not (Test-SafeRel ([string]$f.path))) { throw "$(T 'upd_bad_path'): $($f.path)" }
    }
    $stage = New-StageDir
    try {
        Download-Files $files $stage $null
        $dst = Join-Path $SkillsDir $name
        if (-not (Test-Path -LiteralPath $SkillsDir)) { New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null }
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $stage "skills\$name") -Destination $dst -Recurse -Force
        $Cfg.skills[$name] = [string]$s.rev; Save-Settings
    } finally {
        Remove-StageDir $stage
    }
}
function Remove-Skill([string]$name) {
    $dst = Join-Path $SkillsDir $name
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    [void]$Cfg.skills.Remove($name); Save-Settings
}
function Count-LocalSkills {
    if (-not (Test-Path -LiteralPath $SkillsDir)) { return 0 }
    @(Get-ChildItem -LiteralPath $SkillsDir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }).Count
}

# ───────── аккаунт ─────────
function Get-Account {
    $f = Join-Path $env:USERPROFILE '.claude.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    # Весь файл PowerShell 5.1 не разберёт (ключи-пути, различающиеся регистром), поэтому вырезаем только oauthAccount.
    try {
        $txt = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
        $at = $txt.IndexOf('"oauthAccount"'); if ($at -lt 0) { return $null }
        $st = $txt.IndexOf('{', $at); if ($st -lt 0) { return $null }
        $depth = 0; $inStr = $false; $esc = $false
        for ($i = $st; $i -lt $txt.Length; $i++) {
            $c = $txt[$i]
            if ($inStr) { if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }; continue }
            if ($c -eq '"') { $inStr = $true } elseif ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return ($txt.Substring($st, $i - $st + 1) | ConvertFrom-Json) } }
        }
    } catch {}
    $null
}
function Plan-Name([string]$t) {
    switch -regex ($t) {
        '^claude_max' { 'Max' } '^claude_pro' { 'Pro' } '^claude_team' { 'Team' } '^claude_enterprise' { 'Enterprise' }
        '^$' { '' } default { (Get-Culture).TextInfo.ToTitleCase(($t -replace '^claude_', '' -replace '_', ' ')) }
    }
}
function Billing-Name([string]$b) {
    switch -regex ($b) {
        '^google_play' { 'Google Play' } '^apple' { 'App Store' } '^stripe' { 'Stripe' } '^$' { '' }
        default { $b -replace '_subscription$', '' -replace '_', ' ' }
    }
}
function Format-Date([string]$iso) {
    try {
        $ci = [Globalization.CultureInfo]::GetCultureInfo($(if ($Cfg.lang -eq 'ru') { 'ru-RU' } else { 'en-US' }))
        [DateTimeOffset]::Parse($iso, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime.ToString('d MMM yyyy', $ci)
    } catch { '' }
}

# ═════════════════════════ запуск Claude ═════════════════════════
function Wait-AnyKey { [Console]::WriteLine("`n  $Dim$(T 'press_any')$R"); [void][Console]::ReadKey($true) }
function Start-Claude([string]$path, [string[]]$cliArgs) {
    Clear-Screen
    Input-Restore
    [Console]::CursorVisible = $true
    [Console]::WriteLine("`n  $Clay$($G.Star)$R $Bold${Ivory}Claude Code$R  $Dim$($G.Dot)  $(Format-Path $path)$R`n")
    # какую сессию открываем: нужно, чтобы не подключить строку лимитов дважды
    $sid = $null
    if ($cliArgs.Count -ge 2 -and $cliArgs[0] -eq '--resume') { $sid = $cliArgs[1] }
    elseif ($cliArgs -contains '--continue') {
        $key = (Normalize-Path $path).ToLowerInvariant()
        $info = Get-ClaudeFolders | Where-Object { $_.Path.ToLowerInvariant() -eq $key } | Select-Object -First 1
        if ($info) {
            $sid = @(foreach ($d in $info.Dirs) { Get-ChildItem -LiteralPath $d -Filter *.jsonl -File -ErrorAction SilentlyContinue }) |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty BaseName
        }
    }
    $all = @($cliArgs) + @(Get-LaunchArgs $sid) | Where-Object { $_ -ne $null }
    $env:CCL_LANG = [string]$Cfg.lang
    Push-Location -LiteralPath $path
    [Environment]::CurrentDirectory = $path
    try { & $ClaudeExe @all }
    catch { [Console]::WriteLine("  $Red$(T 'start_failed')$R $($_.Exception.Message)"); Wait-AnyKey }
    finally { Pop-Location; [Console]::Write($R) }
}
function Describe-Launch {
    $parts = @()
    if ($Cfg.model -ne 'default') { $parts += (Value-Label 'model' $Cfg.model) }
    if ($Cfg.permissionMode -ne 'default') { $parts += (Value-Label 'permissionMode' $Cfg.permissionMode) }
    $parts -join " $($G.Dot) "
}

# ═════════════════════════ экраны ═════════════════════════
function Value-Label([string]$key, $v) {
    switch ($key) {
        'model'          { if ($v -eq 'default') { T 'val_default' } else { (Get-Culture).TextInfo.ToTitleCase([string]$v) } }
        'permissionMode' { switch ([string]$v) { 'default' { T 'val_default' } 'manual' { T 'perm_manual' } 'acceptEdits' { T 'perm_accept' } 'auto' { T 'perm_auto' } 'plan' { T 'perm_plan' } default { $v } } }
        'lang'           { if ($v -eq 'ru') { 'Русский' } else { 'English' } }
        'projects'       { if ($v -eq 'auto') { T 'val_auto' } else { [string]$v } }
        'defaultAction'  { if ($v -eq 'continue') { T 'continue' } else { T 'new_session' } }
        'greeting'       { if ($v) { T 'val_on' } else { T 'val_off' } }
        'showLimits'     { if ($v) { T 'val_on' } else { T 'val_off' } }
        'limitsBar'      { if ($v) { T 'val_on' } else { T 'val_off' } }
        'autoUpdate'     { if ($v) { T 'val_on' } else { T 'val_off' } }
        default          { [string]$v }
    }
}
function Step-Option([string]$key, [int]$dir) {
    $vals = $Opts[$key]
    $i = [array]::IndexOf($vals, $Cfg[$key]); if ($i -lt 0) { $i = 0 }
    $Cfg[$key] = $vals[($i + $dir + $vals.Count) % $vals.Count]
    Save-Settings
}

function Show-Missing {
    while ($true) {
        $hasGit = [bool](Get-Command git.exe -ErrorAction SilentlyContinue)
        $mHeader = { param($W) Box @('', (Brand $W), '', "   $Ivory$(T 'missing_title')$R", "   $Muted$(T 'missing_sub')$R", '') $W }
        $mSections = {
            param($q)
            $items = @(
                (MkItem -Label (T 'install_claude') -Sub "$(T 'install_claude_sub'): $InstallCmd" -Icon $G.New -Data @{ Kind = 'install' })
            )
            if (-not $hasGit) { $items += MkItem -Label (T 'get_git') -Sub (T 'get_git_sub') -Icon $G.Open -Data @{ Kind = 'git' } }
            $items += MkItem -Label (T 'open_docs') -Sub $DocsUrl -Icon $G.Open -Data @{ Kind = 'docs' }
            $items += MkItem -Label (T 'check_again') -Icon $G.Cont -Data @{ Kind = 'check' }
            $items += MkItem -Label (T 'exit') -Meta 'esc' -Icon $G.Exit -Data @{ Kind = 'exit' }
            @(MkSection '' $items)
        }
        $pick = Run-Screen -Header $mHeader -Sections $mSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_exit')))
        if (-not $pick -or $pick.Item.Kind -eq 'exit') { return $false }
        switch ($pick.Item.Kind) {
            'install' {
                Clear-Screen; Input-Restore; [Console]::CursorVisible = $true
                [Console]::WriteLine("`n  $Clay$($G.Star)$R $Ivory$(T 'installing')$R`n")
                try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $InstallCmd } catch {}
                $env:Path = "$env:Path;$(Join-Path $env:USERPROFILE '.local\bin')"
                Find-Claude
                if ($ClaudeExe) { return $true }
                [Console]::WriteLine("`n  $Amber$(T 'not_found_after')$R"); Wait-AnyKey
            }
            'git'   { Start-Process $GitUrl }
            'docs'  { Start-Process $DocsUrl }
            'check' { Find-Claude; if ($ClaudeExe) { return $true } }
        }
    }
}

# ═════════════════════════ проверка компонентов ═════════════════════════
# Вместо молчаливого «не работает»: что не найдено, где искали и чем это починить.
# State: ok | off | info | warn | err. Проблемы: warn и err.
$WtStoreUrl = 'https://aka.ms/terminal'
$HealthCount = 0
function Get-Health {
    $hl = New-Object Collections.Generic.List[object]
    $add = { param($st, $nm, $dt, $fx) $hl.Add([pscustomobject]@{ State = $st; Name = $nm; Detail = [string]$dt; Fix = $fx }) }
    if ($SettingsError) { & $add 'err' (T 'h_settings') (TF 'h_settings_bad' $SettingsError) 'reset' }
    if ($ClaudeExe) { & $add 'ok' (T 'h_claude') "$(if ($ClaudeVersion) { "v$ClaudeVersion  " })$(Format-Path $ClaudeExe)" $null }
    else { & $add 'err' (T 'h_claude') (T 'h_claude_bad') 'claude' }
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { & $add 'ok' (T 'h_git') '' $null } else { & $add 'warn' (T 'h_git') (T 'h_git_bad') 'git' }
    $hasWt = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
    if ($hasWt) { & $add 'ok' (T 'h_wt') '' $null } else { & $add 'warn' (T 'h_wt') (T 'h_wt_bad') 'wt' }
    $installed = Test-Path -LiteralPath $AppScript
    if ($installed) {
        & $add 'ok' (T 'h_installed') (Format-Path $AppDir) $null
        $frag = Join-Path $FragmentDir 'launcher.json'
        if ($hasWt -and -not (Test-Path -LiteralPath $frag)) { & $add 'warn' (T 'h_profile') (TF 'h_profile_bad' (Format-Path $frag)) 'profile' }
        $lnk = @(Get-ShortcutPaths)[0]
        if (-not (Test-Path -LiteralPath $lnk)) { & $add 'warn' (T 'h_shortcut') (TF 'h_shortcut_bad' (Format-Path $lnk)) 'profile' }
    } else { & $add 'warn' (T 'h_installed') (TF 'h_portable' (Format-Path $PSScriptRoot)) 'install' }
    $where = (@($AppDir, $PSScriptRoot) | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { Format-Path $_ }) -join '; '
    foreach ($md in @(@($ModName, 'showLimits', 'h_mod_usage'), @($BarModName, 'limitsBar', 'h_mod_bar'))) {
        $nm = "$(TF 'h_mod' $md[0]) $($G.Dot) $(T $md[2])"
        if (-not $Cfg[$md[1]]) { & $add 'off' $nm (T 'h_mod_off') $null }
        elseif (Get-ModDir $md[0]) { & $add 'ok' $nm (Format-Path (Get-ModDir $md[0])) $null }
        else { & $add 'warn' $nm (TF 'h_mod_bad' $where) 'download' }
    }
    if (-not (Get-RepairFile)) { & $add 'warn' (T 'h_repair') (TF 'h_repair_bad' $where) 'download' }
    foreach ($xp in @($Cfg.extraPlugins)) {
        $xe = [Environment]::ExpandEnvironmentVariables([string]$xp)
        if (-not (Test-Path -LiteralPath (Join-Path $xe '.claude-plugin\plugin.json'))) { & $add 'warn' (T 'h_plugin') (TF 'h_plugin_bad' $xe) 'settingsfile' }
    }
    foreach ($xf in @($Cfg.extraUsageFiles)) {
        $xe = [Environment]::ExpandEnvironmentVariables([string]$xf)
        if (-not (Test-Path -LiteralPath $xe)) { & $add 'warn' (T 'h_usagefile') (TF 'h_usagefile_bad' $xe) 'settingsfile' }
    }
    foreach ($sn in @($Cfg.skills.Keys)) {
        if (-not (Test-Path -LiteralPath (Join-Path $SkillsDir $sn))) { & $add 'warn' (TF 'h_skill' $sn) (T 'h_skill_bad') 'skills' }
    }
    if (-not (Get-Source)) { & $add 'info' (T 'h_source') (T 'h_source_bad') 'source' }
    else { & $add 'ok' (T 'h_source') (Get-Source) $null }
    $hl.ToArray()
}
function Health-Problems($hs) { @($hs | Where-Object { $_.State -eq 'warn' -or $_.State -eq 'err' }).Count }
function Health-Report($hs) {
    $lines = @("Claude Code Launcher v$AppVersion  |  $([Environment]::OSVersion.VersionString)  |  PowerShell $($PSVersionTable.PSVersion)",
               "script: $PSCommandPath", '')
    foreach ($hi in $hs) {
        $mk = switch ($hi.State) { 'ok' { '[OK]  ' } 'off' { '[off] ' } 'info' { '[i]   ' } 'warn' { '[!]   ' } default { '[X]   ' } }
        $lines += "$mk$($hi.Name)$(if ($hi.Detail) { " - $($hi.Detail)" })"
    }
    $lines -join "`r`n"
}
# Докачивает из репозитория файлы программы, которых нет рядом со скриптом.
function Restore-Missing {
    if (-not (Get-Source)) { return (T 'fix_nosrc') }
    Clear-Screen; Input-Restore
    [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'upd_checking')$R`n")
    $man = Get-Manifest -Fresh
    if (-not $man) { return (TF 'upd_failed' $Upd.Error) }
    $miss = @($man.files | Where-Object {
        $_ -and $_.path -and ([string]$_.path) -notmatch '^(tools|skills)/' -and
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot (([string]$_.path) -replace '/', '\')))
    })
    if ($miss.Count -eq 0) { return (T 'fix_download_none') }
    $stage = New-StageDir
    try {
        Download-Files $miss $stage { param($rel) Write-Step 'ok' $rel }
        foreach ($f in $miss) {
            $rel = ([string]$f.path) -replace '/', '\'
            $dst = Join-Path $PSScriptRoot $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item -LiteralPath (Join-Path $stage $rel) -Destination $dst -Force
        }
    } catch { return (Friendly-Error $_.Exception.Message) }
    finally { Remove-StageDir $stage }
    TF 'fix_downloaded' $miss.Count
}
function Install-ClaudeCode {
    Clear-Screen; Input-Restore; [Console]::CursorVisible = $true
    [Console]::WriteLine("`n  $Clay$($G.Star)$R $Ivory$(T 'installing')$R`n")
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $InstallCmd } catch {}
    $env:Path = "$env:Path;$(Join-Path $env:USERPROFILE '.local\bin')"
    Find-Claude
    if (-not $ClaudeExe) { [Console]::WriteLine("`n  $Amber$(T 'not_found_after')$R"); Wait-AnyKey }
}
function Show-Health {
    $hsSel = 0; $hsNotice = ''
    while ($true) {
        $hsList = @(Get-Health)
        $script:HealthCount = Health-Problems $hsList
        $hsHeader = {
            param($W)
            $lines = @('', (Brand $W $AppName), '', "   $Bold$Ivory$(T 'health_title')$R", "   $Muted$(FitEnd (T 'health_hdr_sub') ($W - 12))$R", '')
            foreach ($hi in $hsList) {
                $mk = switch ($hi.State) { 'ok' { "$Green$($G.Ok)" } 'off' { "$Dim$($G.Dot)" } 'info' { "$Muted$($G.Dot)" } 'warn' { "$Amber!" } default { "$Red$($G.Err)" } }
                $nc = if ($hi.State -eq 'ok' -or $hi.State -eq 'off') { $Text2 } else { $Ivory }
                $dc = switch ($hi.State) { 'warn' { $Amber } 'err' { $Red } default { $Dim } }
                $nmW = [math]::Min(40, [math]::Max(18, $hi.Name.Length + 2))
                $room = $W - 16 - $nmW
                $dl = @(if ($hi.Detail) { Wrap-Text $hi.Detail $room } else { @() })
                if ($dl.Count -le 1 -and $hi.Name.Length + 2 + ([string]$dl[0]).Length -le $W - 16) {
                    $lines += "   $mk$R  $nc$($hi.Name.PadRight($nmW))$R$dc$($dl -join '')$R"
                } else {
                    $lines += "   $mk$R  $nc$($hi.Name)$R"
                    foreach ($dln in (Wrap-Text $hi.Detail ($W - 18))) { $lines += "      $dc$(FitStart $dln ($W - 18))$R" }
                }
            }
            $pc = Health-Problems $hsList
            $lines += ''
            if ($pc -eq 0) { $lines += "   $Green$($G.Ok) $(T 'health_ok')$R" }
            if ($hsNotice) { $lines += "   $Green$($G.Ok) $(FitEnd $hsNotice ($W - 14))$R" }
            Box ($lines + '') $W
        }
        $hsSections = {
            param($q)
            $its = @(); $seen = @{}
            $fixDefs = @{
                download     = @('fix_download', 'fix_download_sub', $G.Down)
                claude       = @('fix_claude', 'install_claude_sub', $G.New)
                git          = @('fix_git', 'get_git_sub', $G.Open)
                wt           = @('fix_wt', '', $G.Open)
                reset        = @('fix_reset', 'fix_reset_sub', $G.Cont)
                profile      = @('fix_profile', 'fit_window_sub', $G.Home)
                install      = @('fix_install', 'fix_install_sub', $G.New)
                settingsfile = @('fix_settings_open', '', $G.Open)
                skills       = @('fix_skills', 'skills_sub', $G.Skill)
                source       = @('upd_source', 'upd_source_sub', $G.Opt)
            }
            foreach ($hi in $hsList) {
                if (-not $hi.Fix -or $seen.ContainsKey($hi.Fix)) { continue }
                $seen[$hi.Fix] = $true
                $fd = $fixDefs[$hi.Fix]
                $its += MkItem -Label (T $fd[0]) -Sub $(if ($fd[1]) { T $fd[1] } else { '' }) -Icon $fd[2] -Data @{ Kind = $hi.Fix }
            }
            $more = @((MkItem -Label (T 'copy_report') -Sub (T 'copy_report_sub') -Icon $G.All -Data @{ Kind = 'report' }))
            if ((Get-RepairFile) -and $ClaudeExe) { $more += MkItem -Label (T 'repair') -Sub (T 'repair_sub') -Icon $G.Star -Data @{ Kind = 'repair' } }
            $more += MkItem -Label (T 'back') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' }
            @((MkSection '' $its), (MkSection '' $more))
        }
        $pick = Run-Screen -Header $hsHeader -Sections $hsSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_back'))) -Start $hsSel
        if (-not $pick -or $pick.Item.Kind -eq 'back') { return }
        $hsSel = $pick.Index; $hsNotice = ''
        switch ($pick.Item.Kind) {
            'download' { $hsNotice = Restore-Missing }
            'claude'   { Install-ClaudeCode }
            'git'      { Start-Process $GitUrl }
            'wt'       { Start-Process $WtStoreUrl }
            'reset'    {
                try {
                    if (Test-Path -LiteralPath $SettingsFile) { Move-Item -LiteralPath $SettingsFile -Destination (Join-Path $AppDir 'settings.bak.json') -Force }
                    $script:SettingsError = ''; Save-Settings; $hsNotice = T 'fix_reset_done'
                } catch { $hsNotice = $_.Exception.Message }
            }
            'profile'  {
                try {
                    if (Get-Command wt.exe -ErrorAction SilentlyContinue) { Write-Fragment }
                    Write-Shortcuts; $hsNotice = T 'fix_profile_done'
                } catch { $hsNotice = $_.Exception.Message }
            }
            'install'  {
                Clear-Screen; Input-Restore
                & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Install -Quiet
                Wait-AnyKey
            }
            'settingsfile' {
                if (-not (Test-Path -LiteralPath $SettingsFile)) { Save-Settings }
                Start-Process notepad.exe -ArgumentList "`"$SettingsFile`""
            }
            'skills'   { Show-Skills }
            'source'   { Edit-Source }
            'report'   { try { Set-Clipboard -Value (Health-Report $hsList); $hsNotice = T 'report_copied' } catch { $hsNotice = $_.Exception.Message } }
            'repair'   { $rf = Get-RepairFile; Start-Claude (Split-Path $rf) @((T 'repair_prompt')) }
        }
    }
}

# Вопрос «да / отмена». Возвращает $true, если выбрано «да».
function Confirm-Ask([string]$question, [string]$detail, [string]$yesLabel) {
    $cqHeader = { param($W) Box @('', (Brand $W $AppName), '', "   $Bold$Ivory$(FitEnd $question ($W - 12))$R", "   $Muted$(FitEnd $detail ($W - 12))$R", '') $W }
    $cqSections = { param($q) @(MkSection '' @(
        (MkItem -Label (T 'cancel') -Icon $G.Back -Data @{ Kind = 'no' }),
        (MkItem -Label $yesLabel -Icon $G.Ok -Data @{ Kind = 'yes' }))) }
    $cq = Run-Screen -Header $cqHeader -Sections $cqSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_back')))
    [bool]($cq -and $cq.Item.Kind -eq 'yes')
}

function Edit-Source {
    Clear-Screen; Input-Restore; [Console]::CursorVisible = $true
    [Console]::WriteLine("`n  $Clay$($G.Star)$R $Bold$Ivory$(T 'upd_source')$R`n")
    [Console]::WriteLine("  $Text2$(T 'src_prompt')$R")
    [Console]::WriteLine("  $Dim$(T 'src_hint')$R")
    [Console]::WriteLine("  $Dim$(TF 'src_current' (Format-Source (Get-Source)))$R`n")
    [Console]::Write("  $Clay>$R ")
    $line = $null
    try { $line = [Console]::ReadLine() } catch {}
    [Console]::CursorVisible = $false
    if ($null -eq $line) { return }
    $line = $line.Trim().Trim('"').Trim()
    if (-not $line) { return }
    if ($line -eq '-') { $Cfg.updateSource = '' }
    else {
        if ($line -match '^https?://github\.com/([^/\s]+/[^/\s#?]+?)(\.git)?(/tree/([^/\s]+))?/?$') {
            $line = $Matches[1]; if ($Matches[4]) { $line += '@' + $Matches[4] }
        }
        $Cfg.updateSource = $line
    }
    Save-Settings
    Wait-UpdateCheck
    $Upd.State = 'idle'; $Upd.Manifest = $null; $Upd.Time = $null
    Start-UpdateCheck
}

# Экран обновления: что нового, установить / позже / пропустить.
function Show-Update {
    $upSel = 0
    if ($Upd.State -eq 'idle' -or $Upd.State -eq 'nosrc') { Start-UpdateCheck }
    while ($true) {
        $upHeader = {
            param($W)
            $um = $Upd.Manifest
            $lines = @('', (Brand $W $AppName), '', "   $Bold$Ivory$(T 'upd_title')$R")
            switch ($Upd.State) {
                'available' {
                    $lines += "   $Green$($G.Upd) $(TF 'upd_avail' "v$($um.version)")$R"
                    $ft = "   $Dim$(TF 'upd_from_to' $AppVersion $G.To $um.version)"
                    if ($um.date) { $ft += "  $($G.Dot)  $($um.date)" }
                    $lines += "$ft$R"
                    $notes = @(Update-Notes $um $W)
                    if ($notes.Count) { $lines += ''; $lines += "   $Muted$Bold$(T 'upd_whatsnew')$R"; $lines += $notes }
                }
                'latest'   { $lines += "   $Green$($G.Ok) $(TF 'upd_latest' $AppVersion)$R" }
                'nosrc'    { $lines += "   $Amber$(FitEnd (T 'upd_nosrc') ($W - 12))$R" }
                'error'    { $lines += "   $Red$(FitEnd (TF 'upd_failed' $Upd.Error) ($W - 12))$R" }
                default    { $lines += "   $Muted$(T 'upd_checking')$R" }
            }
            $lines += "   $Dim$(FitEnd (TF 'inf_source' (Format-Source (Get-Source))) ($W - 12))$R"
            Box ($lines + '') $W
        }
        $upSections = {
            param($q)
            $its = @()
            if ($Upd.State -eq 'available') {
                $its += MkItem -Label (T 'upd_install') -Sub (T 'upd_install_sub') -Icon $G.Upd -Data @{ Kind = 'install' }
                $its += MkItem -Label (T 'upd_later') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' }
                $its += MkItem -Label (T 'upd_skip') -Sub (T 'upd_skip_sub') -Icon $G.Exit -Data @{ Kind = 'skip' }
            } else {
                $its += MkItem -Label (T 'upd_check_again') -Icon $G.Cont -Data @{ Kind = 'check' }
                $its += MkItem -Label (T 'upd_source') -Sub (T 'upd_source_sub') -Meta (Format-Source (Get-Source)) -Icon $G.Opt -Data @{ Kind = 'source' }
                $its += MkItem -Label (T 'back') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' }
            }
            @(MkSection '' $its)
        }
        $pick = Run-Screen -Header $upHeader -Sections $upSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_back'))) -Start $upSel
        if (-not $pick -or $pick.Item.Kind -eq 'back') { return }
        $upSel = $pick.Index
        switch ($pick.Item.Kind) {
            'install' { if (Install-Update) { Restart-Launcher } }
            'skip'    { $Cfg.skipVersion = [string]$Upd.Manifest.version; Save-Settings; return }
            'check'   {
                Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'upd_checking')$R")
                Check-UpdateNow; $upSel = 0
            }
            'source'  { Edit-Source; Wait-UpdateCheck }
        }
    }
}

# Каталог скиллов из репозитория.
function Show-Skills {
    $skSel = 0; $skNotice = ''
    Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'sk_loading')$R")
    $skMan = Get-Manifest
    while ($true) {
        $skList = @(if ($skMan) { $skMan.skills | Where-Object { $_ -and $_.name } })
        $skHeader = {
            param($W)
            $lines = @('', (Brand $W $AppName), '', "   $Bold$Ivory$(T 'skills_title')$R", "   $Muted$(FitEnd (T 'skills_hdr_sub') ($W - 12))$R")
            if ($Upd.State -eq 'nosrc') { $lines += "   $Amber$(FitEnd (T 'upd_nosrc') ($W - 12))$R" }
            elseif (-not $skMan -and $Upd.State -eq 'error') { $lines += "   $Red$(FitEnd (TF 'upd_failed' $Upd.Error) ($W - 12))$R" }
            elseif ($skMan -and $skList.Count -eq 0) { $lines += "   $Dim$(T 'sk_empty')$R" }
            if ($skNotice) { $lines += "   $Green$($G.Ok) $(FitEnd $skNotice ($W - 14))$R" }
            Box ($lines + '') $W
        }
        $skSections = {
            param($q)
            $its = @(foreach ($sk in $skList) {
                $st = Skill-State $sk
                $meta = switch ($st) { 'ok' { T 'sk_installed' } 'update' { T 'sk_update' } 'local' { T 'sk_local' } default { T 'sk_install' } }
                $ic = switch ($st) { 'ok' { $G.Ok } 'update' { $G.Upd } 'local' { $G.Skill } default { $G.New } }
                MkItem -Label ([string]$sk.name) -Sub (Lang-Text $sk.description) -Meta $meta -Icon $ic -Data @{ Kind = 'skill'; Skill = $sk; State = $st }
            })
            $more = @()
            if ($skList.Count -gt 1) { $more += MkItem -Label (T 'sk_install_all') -Sub (T 'sk_install_all_sub') -Icon $G.Down -Data @{ Kind = 'all' } }
            $more += MkItem -Label (T 'sk_open_dir') -Meta (Format-Path $SkillsDir) -Icon $G.Open -Data @{ Kind = 'dir' }
            $more += MkItem -Label (T 'sk_reload') -Icon $G.Cont -Data @{ Kind = 'reload' }
            if ($Upd.State -eq 'nosrc' -or ($Upd.State -eq 'error' -and -not $skMan)) {
                $more += MkItem -Label (T 'upd_source') -Sub (T 'upd_source_sub') -Meta (Format-Source (Get-Source)) -Icon $G.Opt -Data @{ Kind = 'source' }
            }
            $more += MkItem -Label (T 'back') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' }
            @((MkSection (T 'sk_catalog') $its (TF 'sk_count' $skList.Count)), (MkSection '' $more))
        }
        $keys = @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_install')), @('del', (T 'k_remove')), @('esc', (T 'k_back')))
        $pick = Run-Screen -Header $skHeader -Sections $skSections -Keys $keys -Start $skSel -AllowDelete
        if (-not $pick -or $pick.Item.Kind -eq 'back') { return }
        $skSel = $pick.Index; $skNotice = ''
        $it = $pick.Item
        if ($pick.Action -eq 'delete') {
            if ($it.Kind -ne 'skill') { continue }
            $nm = [string]$it.Skill.name
            if (-not $Cfg.skills.ContainsKey($nm)) { $skNotice = T 'sk_not_ours'; continue }
            if (Confirm-Ask (TF 'sk_remove_q' $nm) (T 'sk_remove_sub') (T 'yes_remove')) {
                try { Remove-Skill $nm; $skNotice = TF 'sk_removed' $nm } catch { $skNotice = $_.Exception.Message }
            }
            continue
        }
        switch ($it.Kind) {
            'skill' {
                $nm = [string]$it.Skill.name
                if ($it.State -eq 'ok') { $skNotice = TF 'sk_uptodate' $nm; break }
                if ($it.State -eq 'local' -and -not (Confirm-Ask (TF 'sk_overwrite_q' $nm) (T 'sk_overwrite_sub') (T 'yes_replace'))) { break }
                Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Ivory$(TF 'sk_installing' $nm)$R")
                try { Install-Skill $it.Skill; $skNotice = TF 'sk_done' $nm } catch { $skNotice = $_.Exception.Message }
            }
            'all' {
                $cnt = 0; $errs = @()
                foreach ($sk in $skList) {
                    $st = Skill-State $sk
                    if ($st -ne 'none' -and $st -ne 'update') { continue }
                    Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Ivory$(TF 'sk_installing' $sk.name)$R")
                    try { Install-Skill $sk; $cnt++ } catch { $errs += "$($sk.name): $($_.Exception.Message)" }
                }
                $skNotice = if ($errs.Count) { $errs -join '; ' } elseif ($cnt) { TF 'sk_all_done' $cnt } else { T 'sk_all_none' }
            }
            'dir' {
                if (-not (Test-Path -LiteralPath $SkillsDir)) { New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null }
                Start-Process explorer.exe -ArgumentList "`"$SkillsDir`""
            }
            'reload' {
                Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'sk_loading')$R")
                $skMan = Get-Manifest -Fresh
            }
            'source' {
                Edit-Source
                Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'sk_loading')$R")
                $skMan = Get-Manifest -Fresh
            }
        }
    }
}

# Сведения: аккаунт, лимиты, версии.
function Show-Info {
    $inSel = 0
    while ($true) {
        $inAcc = Get-Account
        $inHeader = {
            param($W)
            $lbl = { param($a, $b) "   $Text2$(([string]$a).PadRight(21))$R$b" }
            $lines = @('', (Brand $W $AppName), '', "   $Bold$Ivory$(T 'info_title')$R", "   $Muted$(FitEnd (T 'info_hdr_sub') ($W - 12))$R", '')
            $lines += "   $Muted$Bold$(T 'inf_account')$R"
            if ($inAcc -and ($inAcc.emailAddress -or $inAcc.displayName)) {
                $who = @(@($inAcc.displayName, $inAcc.emailAddress) | Where-Object { $_ }) -join "  $Dim$($G.Dot)$R  $Ivory"
                $lines += "   $Ivory$who$R"
                $plan = Plan-Name ([string]$inAcc.organizationType)
                $pl = @()
                if ($plan) { $pl += "$Bold$Ivory$plan$R" }
                $bn = Billing-Name ([string]$inAcc.billingType); if ($bn) { $pl += "$Text2$bn$R" }
                if ($inAcc.subscriptionCreatedAt) { $sd = Format-Date ([string]$inAcc.subscriptionCreatedAt); if ($sd) { $pl += "$Dim$(TF 'inf_since' $sd)$R" } }
                if ($pl.Count) { $lines += (& $lbl (T 'inf_plan') ($pl -join "  $Dim$($G.Dot)$R  ")) }
                $ex = if ($inAcc.hasExtraUsageEnabled) { "$Green$(T 'val_on')$R" } else { "$Dim$(T 'val_off')$R" }
                if ($inAcc.organizationRole) { $ex += "  $Dim$($G.Dot)  $(TF 'inf_role' $inAcc.organizationRole)$R" }
                $lines += (& $lbl (T 'inf_extra') $ex)
            } else { $lines += "   $Dim$(FitEnd (T 'inf_no_account') ($W - 12))$R" }
            $lines += ''
            $lines += "   $Muted$Bold$(T 'inf_limits')$R"
            $ul = @(Usage-Lines $W -Always | Where-Object { $_ -ne '' })
            $lines += $ul
            $lines += ''
            $lines += "   $Muted$Bold$(T 'inf_apps')$R"
            $cv = if ($ClaudeVersion) { "$Ivory" + "v$ClaudeVersion$R" } else { "$Dim$(T 'no')$R" }
            if ($ClaudeExe) { $cv += "  $Dim$(FitStart (Format-Path $ClaudeExe) ($W - 50))$R" }
            $lines += (& $lbl 'Claude Code' $cv)
            $chk = if ($Cfg.lastCheck) { try { TF 'inf_checked' (Format-Ago ([DateTimeOffset]::Parse([string]$Cfg.lastCheck, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime)) } catch { '' } } else { T 'inf_never' }
            $lv = "$Ivory" + "v$AppVersion$R"
            if (Update-Pending) { $lv += "  $Green$($G.Upd) $(TF 'upd_meta_new' $Upd.Manifest.version)$R" }
            $lines += (& $lbl (T 'inf_launcher') $lv)
            $srcTxt = FitEnd (Format-Source (Get-Source)) ([math]::Max(12, $W - 40 - $chk.Length))
            $lines += (& $lbl (T 'sec_updates') "$Text2$srcTxt$R  $Dim$($G.Dot)  $chk$R")
            $lines += (& $lbl (T 'inf_skills') "$Text2$(TF 'inf_skills_val' (Count-LocalSkills) $Cfg.skills.Count)$R")
            $hasGit = Get-Command git.exe -ErrorAction SilentlyContinue
            $hasWt = Get-Command wt.exe -ErrorAction SilentlyContinue
            $yn = { param($x) if ($x) { "$Green$(T 'yes')$R" } else { "$Amber$(T 'no')$R" } }
            $lines += (& $lbl 'Git' (& $yn $hasGit)) + "     $Text2" + 'Windows Terminal  ' + (& $yn $hasWt)
            Box ($lines + '') $W
        }
        $inSections = {
            param($q)
            @(MkSection '' @(
                (MkItem -Label (T 'refresh') -Sub (T 'refresh_sub') -Icon $G.Cont -Data @{ Kind = 'refresh' }),
                (MkItem -Label (T 'open_usage') -Sub (T 'open_usage_sub') -Icon $G.Open -Data @{ Kind = 'web' }),
                (MkItem -Label (T 'back') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' })))
        }
        $pick = Run-Screen -Header $inHeader -Sections $inSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_back'))) -Start $inSel
        if (-not $pick -or $pick.Item.Kind -eq 'back') { return }
        $inSel = $pick.Index
        switch ($pick.Item.Kind) {
            'web'     { Start-Process $UsagePageUrl }
            'refresh' { }
        }
    }
}

# Политика использования: страница в репозитории, без него: локальный POLICY.md.
function Open-Policy {
    $s = Get-Source
    if ($s -and $s -notmatch '^[a-zA-Z]:[\\/]|^\\\\|^https?://') {
        $repo = $s; $branch = 'main'
        if ($s -match '^(.+?)@(.+)$') { $repo = $Matches[1]; $branch = $Matches[2] }
        Start-Process "https://github.com/$repo/blob/$branch/POLICY.md"; return
    }
    foreach ($d in @($AppDir, $PSScriptRoot)) {
        $f = Join-Path $d 'POLICY.md'
        if ($d -and (Test-Path -LiteralPath $f)) { Start-Process notepad.exe -ArgumentList "`"$f`""; return }
    }
}

function Show-Settings([switch]$First) {
    $setSel = 0; $notice = ''
    while ($true) {
        $installed = Test-Path -LiteralPath $AppScript
        if (-not $First) { $script:HealthCount = Health-Problems (Get-Health) }
        $setHeader = {
            param($W)
            $t = if ($First) { T 'welcome_title' } else { T 'settings_title' }
            $sub = if ($First) { T 'welcome_sub' } else { T 'settings_sub' }
            $lines = @('', (Brand $W $AppName), '', "   $Bold$Ivory$t$R", "   $Muted$(FitEnd $sub ($W - 12))$R")
            if ($notice) { $lines += "   $Green$($G.Ok) $(FitEnd $notice ($W - 14))$R" }
            if (-not $First -and (Update-Pending)) { $lines += "   $Green$($G.Upd) $(TF 'upd_home' $Upd.Manifest.version)$R" }
            Box ($lines + '') $W
        }
        $setSections = {
            param($q)
            $opt = { param($key, $lbl)
                MkItem -Label (T $lbl) -Sub (T "${lbl}_sub") -Meta "$($G.ArL) $(Value-Label $key $Cfg[$key]) $($G.ArR)" -Icon $G.Opt -Data @{ Kind = 'opt'; Key = $key }
            }
            $updMeta = switch ($Upd.State) {
                'available' { TF 'upd_meta_new' $Upd.Manifest.version }
                'latest'    { TF 'upd_meta_latest' $AppVersion }
                'nosrc'     { T 'upd_meta_none' }
                'error'     { T 'upd_meta_err' }
                default     { if (-not (Get-Source)) { T 'upd_meta_none' } else { "v$AppVersion" } }
            }
            $account = @((MkItem -Label (T 'info') -Sub (T 'info_sub') -Meta (Usage-Plain) -Icon $G.Info -Data @{ Kind = 'info' }))
            $updates = @(
                (MkItem -Label (T 'check_upd') -Sub (T 'check_upd_sub') -Meta $updMeta -Icon $G.Upd -Data @{ Kind = 'checkupd' }),
                (& $opt 'autoUpdate' 's_autoUpdate'),
                (MkItem -Label (T 'upd_source') -Sub (T 'upd_source_sub') -Meta (FitStart (Format-Source (Get-Source)) 34) -Icon $G.Opt -Data @{ Kind = 'source' })
            )
            $skillsSec = @((MkItem -Label (T 'skills') -Sub (T 'skills_sub') -Meta (TF 'skills_meta' $Cfg.skills.Count) -Icon $G.Skill -Data @{ Kind = 'skills' }))
            $hMeta = if ($HealthCount -gt 0) { TF 'health_meta' $HealthCount } else { T 'health_ok' }
            $tools = @((MkItem -Label (T 'health') -Sub (T 'health_sub') -Meta $hMeta -Icon $G.Ok -Data @{ Kind = 'health' }))
            $tools += MkItem -Label (T 'update_claude') -Sub (T 'update_sub') -Icon $G.Cont -Data @{ Kind = 'update' }
            if ($installed) { $tools += MkItem -Label (T 'fit_window') -Sub (T 'fit_window_sub') -Icon $G.Home -Data @{ Kind = 'fit' } }
            if (@($Cfg.hidden).Count) { $tools += MkItem -Label (T 'unhide') -Meta (TF 'unhide_meta' @($Cfg.hidden).Count) -Icon $G.Back -Data @{ Kind = 'unhide' } }
            $tools += MkItem -Label (T 'open_dir') -Meta (Format-Path $AppDir) -Icon $G.Open -Data @{ Kind = 'opendir' }
            if (Get-RepairFile) {
                $tools += MkItem -Label (T 'repair') -Sub (T 'repair_sub') -Icon $G.Star -Data @{ Kind = 'repair' }
                $tools += MkItem -Label (T 'copy_prompt') -Sub (T 'copy_prompt_sub') -Icon $G.All -Data @{ Kind = 'copyprompt' }
            }
            $tools += MkItem -Label (T 'policy') -Sub (T 'policy_sub') -Icon $G.All -Data @{ Kind = 'policy' }
            if ($installed) { $tools += MkItem -Label (T 'uninstall') -Sub (T 'uninstall_sub') -Icon $G.Exit -Data @{ Kind = 'uninstall' } }
            $secs = @()
            if (-not $First) { $secs += MkSection (T 'sec_account') $account }
            $secs += @(
                (MkSection (T 'sec_launch') @((& $opt 'model' 's_model'), (& $opt 'permissionMode' 's_perm'))),
                (MkSection (T 'sec_view') @((& $opt 'lang' 's_lang'), (& $opt 'limitsBar' 's_bar'), (& $opt 'showLimits' 's_limits'), (& $opt 'projects' 's_projects'), (& $opt 'defaultAction' 's_default'), (& $opt 'greeting' 's_greeting')))
            )
            if (-not $First) {
                $secs += MkSection (T 'sec_updates') $updates
                $secs += MkSection (T 'sec_skills') $skillsSec
                $secs += MkSection (T 'sec_tools') $tools
            }
            $secs += MkSection '' @((MkItem -Label (T 'done') -Meta 'esc' -Icon $G.Ok -Data @{ Kind = 'done' }))
            $secs
        }
        $keys = @(@("$($G.Up)$($G.Down)", (T 'k_select')), @("$($G.ArL) $($G.ArR) enter", (T 'k_change')), @('esc', (T 'k_done')))
        $pick = Run-Screen -Header $setHeader -Sections $setSections -Keys $keys -Start $setSel -AllowLR
        if (-not $pick) { return }
        $setSel = $pick.Index; $notice = ''
        $it = $pick.Item
        switch ($it.Kind) {
            'opt'     {
                Step-Option $it.Key $(if ($pick.Action -eq 'left') { -1 } else { 1 })
                if ($it.Key -eq 'autoUpdate' -and $Cfg.autoUpdate -and $Upd.State -eq 'idle') { Start-UpdateCheck }
            }
            'done'    { return }
            'info'     { if ($pick.Action -eq 'enter') { Show-Info } }
            'health'   { if ($pick.Action -eq 'enter') { Show-Health } }
            'policy'   { if ($pick.Action -eq 'enter') { Open-Policy } }
            'skills'   { if ($pick.Action -eq 'enter') { Show-Skills } }
            'source'   { if ($pick.Action -eq 'enter') { Edit-Source } }
            'checkupd' {
                if ($pick.Action -ne 'enter') { continue }
                if ($Upd.State -ne 'available') {
                    Clear-Screen; [Console]::WriteLine("`n  $Clay$($G.Star)$R $Muted$(T 'upd_checking')$R")
                    Check-UpdateNow
                }
                Show-Update
            }
            'update'  {
                if ($pick.Action -ne 'enter') { continue }
                Clear-Screen; Input-Restore; [Console]::CursorVisible = $true
                [Console]::WriteLine("`n  $Clay$($G.Star)$R $Ivory$(T 'update_claude')$R`n")
                if ($ClaudeExe) { try { & $ClaudeExe update } catch { [Console]::WriteLine("  $Red$($_.Exception.Message)$R") } }
                Find-Claude; Wait-AnyKey
            }
            'fit'     { if ($pick.Action -eq 'enter') { try { Write-Shortcuts; $notice = T 'fit_done' } catch { $notice = $_.Exception.Message } } }
            'unhide'  { if ($pick.Action -eq 'enter') { $Cfg.hidden = @(); Save-Settings; $notice = T 'unhide_done' } }
            'repair'  {
                if ($pick.Action -ne 'enter') { continue }
                $rf = Get-RepairFile
                Start-Claude (Split-Path $rf) @((T 'repair_prompt'))
            }
            'copyprompt' {
                if ($pick.Action -ne 'enter') { continue }
                try {
                    $txt = Get-Content -LiteralPath (Get-RepairFile) -Raw -Encoding UTF8
                    $idx = $txt.IndexOf("`n---")
                    if ($idx -ge 0) { $txt = $txt.Substring($idx + 4).TrimStart() }
                    Set-Clipboard -Value $txt
                    $notice = T 'copied'
                } catch { $notice = $_.Exception.Message }
            }
            'opendir' { if ($pick.Action -eq 'enter') { $d = if (Test-Path -LiteralPath $AppDir) { $AppDir } else { $PSScriptRoot }; Start-Process explorer.exe -ArgumentList "`"$d`"" } }
            'uninstall' {
                if ($pick.Action -ne 'enter') { continue }
                $cHeader = { param($W) Box @('', (Brand $W $AppName), '', "   $Bold$Ivory$(T 'uninstall_q')$R", "   $Muted$(T 'uninstall_sub')$R", '') $W }
                $cSections = { param($q) @(MkSection '' @(
                    (MkItem -Label (T 'cancel') -Icon $G.Back -Data @{ Kind = 'no' }),
                    (MkItem -Label (T 'yes_delete') -Icon $G.Exit -Data @{ Kind = 'yes' }))) }
                $c = Run-Screen -Header $cHeader -Sections $cSections -Keys @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('esc', (T 'k_back')))
                if ($c -and $c.Item.Kind -eq 'yes') {
                    Remove-LauncherFiles
                    Clear-Screen; [Console]::CursorVisible = $true
                    [Console]::WriteLine("`n  $Green$($G.Ok)$R $Ivory$(T 'u_done')$R")
                    Wait-AnyKey
                    exit 0
                }
            }
        }
    }
}

function Open-Project([string]$projPath) {
    while ($true) {
        $pKey = (Normalize-Path $projPath).ToLowerInvariant()
        $pInfo = Get-ClaudeFolders | Where-Object { $_.Path.ToLowerInvariant() -eq $pKey } | Select-Object -First 1
        $pSessions = @(Get-FolderSessions $pInfo 7)
        $pLaunch = Describe-Launch

        $pHeader = {
            param($W)
            $stats = if ($pInfo) {
                "$Text2$(Plural $pInfo.Sessions (T 'sessions'))$R  $Dim$($G.Dot)$R  $Text2$(TF 'last_x' (Format-Ago $pInfo.Last))$R"
            } else { "$Text2$(T 'new_project') $Dim$($G.Dot)$Text2 $(T 'no_sessions')$R" }
            if ($pLaunch) { $stats += "  $Dim$($G.Dot)  $(TF 'launch_with' $pLaunch)$R" }
            $statLine = Spread "   $stats" (Usage-Compact) ($W - 8)
            Box @('', (Brand $W (FitEnd (Leaf $projPath) ($W - 30))), "   $Muted$(FitStart (Format-Path $projPath) ($W - 12))$R", '', $statLine, '') $W
        }
        $pSections = {
            param($q)
            $start = @((MkItem -Label (T 'new_session') -Sub (T 'new_session_sub') -Meta 'N' -Icon $G.New -Hot 'N' -Data @{ Kind = 'run'; Args = @() }))
            if ($pInfo) {
                $lastTitle = if ($pSessions.Count) { "$($G.LQ)$($pSessions[0].Title)$($G.RQ)" } else { T 'last_conv' }
                $start += MkItem -Label (T 'continue') -Sub $lastTitle -Meta 'C' -Icon $G.Cont -Hot 'C' -Data @{ Kind = 'run'; Args = @('--continue') }
            }
            $recent = @()
            foreach ($s in ($pSessions | Select-Object -Skip 1 -First 6)) {
                $recent += MkItem -Label $s.Title -Meta (Format-Ago $s.Last) -Icon $G.Sess -Data @{ Kind = 'run'; Args = @('--resume', $s.Id) }
            }
            if ($pInfo) { $recent += MkItem -Label (T 'all_sessions') -Sub (T 'all_sessions_sub') -Meta 'R' -Icon $G.All -Hot 'R' -Data @{ Kind = 'run'; Args = @('--resume') } }
            @(
                (MkSection (T 'sec_start') $start),
                (MkSection (T 'sec_recent_sessions') $recent),
                (MkSection (T 'sec_folder') @(
                    (MkItem -Label (T 'open_explorer') -Meta 'O' -Icon $G.Open -Hot 'O' -Data @{ Kind = 'explorer' }),
                    (MkItem -Label (T 'back_projects') -Meta 'esc' -Icon $G.Back -Data @{ Kind = 'back' })))
            )
        }
        $startSel = if ($Cfg.defaultAction -eq 'continue' -and $pInfo) { 1 } else { 0 }
        $keys = @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_run')), @('n c r o', (T 'k_hot')), @('esc', (T 'k_back')))
        $pick = Run-Screen -Header $pHeader -Sections $pSections -Keys $keys -Start $startSel
        if (-not $pick -or $pick.Item.Kind -eq 'back') { return }
        switch ($pick.Item.Kind) {
            'explorer' { Start-Process explorer.exe -ArgumentList "`"$projPath`"" }
            'run'      { Start-Claude $projPath $pick.Item.Args }
        }
    }
}

# Плашка в шапке главного экрана: «вышло обновление» или «лаунчер обновлён».
$HomeNotice = ''
function Home-Banner([int]$W) {
    if (Update-Pending) {
        $hb = "   $Green$Bold$($G.Upd) $(TF 'upd_home' $Upd.Manifest.version)$NoBold$R  $Dim$($G.Dot)  $(T 'upd_home_hint')$R"
        return @('', $hb)
    }
    $hbOut = @()
    if ($HomeNotice) { $hbOut += @('', "   $Green$($G.Ok) $(FitEnd $HomeNotice ($W - 14))$R") }
    if ($HealthCount -gt 0) {
        if (-not $hbOut.Count) { $hbOut += '' }
        $hbOut += "   $Amber! $(TF 'health_home' $HealthCount)$R  $Dim$($G.Dot)  $(T 'health_home_hint')$R"
    }
    $hbOut
}
function Show-Home {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $homeSel = 0
    while ($true) {
        $hAll = @(Get-ClaudeFolders | Where-Object { @($Cfg.hidden) -notcontains $_.Path })
        $script:HealthCount = Health-Problems (Get-Health)
        $hHeader = {
            param($W)
            $lines = @('', (Brand $W), '')
            if ($Cfg.greeting) { $lines += "   $Ivory$(Greeting)!$R" }
            $lines += "   $Muted$(T 'home_sub')$R"
            $lines += @(Usage-Lines $W)
            $lines += @(Home-Banner $W)
            Box ($lines + '') $W
        }
        $hSections = {
            param($q)
            # строки шапки: пустая + рамка + поиск (3): всё, что не список
            $boxLines = (@('', '', '') + $(if ($Cfg.greeting) { @('') } else { @() }) + @('') + @(Usage-Lines (Get-Width)) + @(Home-Banner (Get-Width)) + @('')).Count + 2
            if (Update-Pending) { $boxLines += 1 }
            if ($HealthCount -gt 0) { $boxLines += 1 }
            $fit = if ($Cfg.projects -eq 'auto') {
                [math]::Max(3, [math]::Floor(([Console]::WindowHeight - 15 - $boxLines) / 2))
            } else { [int]$Cfg.projects }
            $shown = if ($q) { @($hAll | Where-Object { $_.Path -like "*$q*" }) } else { @($hAll | Select-Object -First $fit) }
            $proj = @(foreach ($f in $shown) {
                MkItem -Label (Leaf $f.Path) -Sub (Format-Path (Split-Path -Parent $f.Path)) `
                       -Meta "$(Plural $f.Sessions (T 'sessions'))  $($G.Dot)  $(Format-Ago $f.Last)" `
                       -Icon $G.Proj -Data @{ Kind = 'folder'; Path = $f.Path }
            })
            $note = if ($q) { TF 'found' $proj.Count } elseif ($hAll.Count -gt $fit) { TF 'fit_note' $fit $hAll.Count } elseif ($hAll.Count -eq 0) { T 'no_projects' } else { '' }
            $other = @()
            if (-not $q) {
                if (Update-Pending) {
                    $hFirst = ''
                    $hc = @($Upd.Manifest.changelog | Where-Object { $_ -and [string]$_.version -eq [string]$Upd.Manifest.version }) | Select-Object -First 1
                    if ($hc) { $hn = @($hc.([string]$Cfg.lang)); if (-not $hn[0]) { $hn = @($hc.ru) }; $hFirst = [string]$hn[0] }
                    $other += MkItem -Label (TF 'upd_item' $Upd.Manifest.version) -Sub $hFirst -Meta (T 'upd_item_meta') -Icon $G.Upd -Data @{ Kind = 'update' }
                }
                if ($HealthCount -gt 0) {
                    $other += MkItem -Label (T 'health') -Sub (T 'health_sub') -Meta (TF 'health_meta' $HealthCount) -Icon $G.Err -Data @{ Kind = 'health' }
                }
                $other += @(
                    (MkItem -Label (T 'desktop') -Meta (Format-Path $desktop) -Icon $G.Home -Data @{ Kind = 'desktop' }),
                    (MkItem -Label (T 'browse') -Meta (T 'browse_meta') -Icon $G.Browse -Data @{ Kind = 'browse' }),
                    (MkItem -Label (T 'settings') -Meta (T 'settings_meta') -Icon $G.Gear -Data @{ Kind = 'settings' }),
                    (MkItem -Label (T 'exit') -Meta 'esc' -Icon $G.Exit -Data @{ Kind = 'exit' })
                )
            }
            $recentSec = MkSection (T 'sec_recent') $proj $note
            if ($proj.Count -eq 0 -and -not $q -and $note) { $recentSec = [pscustomobject]@{ Title = (T 'sec_recent'); Items = @(); Note = '' } }
            @($recentSec, (MkSection (T 'sec_more') $other))
        }
        $keys = @(@("$($G.Up)$($G.Down)", (T 'k_select')), @('enter', (T 'k_open')), @('abc', (T 'k_search')), @('del', (T 'k_hide')), @('esc', (T 'k_exit')))
        $pick = Run-Screen -Header $hHeader -Sections $hSections -Keys $keys -Search -AllowDelete -Start $homeSel
        if (-not $pick) { return }
        $homeSel = $pick.Index
        $c = $pick.Item
        if ($pick.Action -eq 'delete') {
            if ($c.Kind -eq 'folder') { $Cfg.hidden = @($Cfg.hidden) + $c.Path; Save-Settings }
            continue
        }
        switch ($c.Kind) {
            'folder'   { Open-Project $c.Path }
            'desktop'  { Open-Project $desktop }
            'browse'   { $t = Select-FolderDialog $desktop; if ($t) { Open-Project $t } }
            'settings' { Show-Settings }
            'update'   { Show-Update }
            'health'   { Show-Health }
            'exit'     { return }
        }
    }
}

# ═════════════════════════ старт ═════════════════════════
Load-Settings
Find-Claude
if ($Uninstall) { Invoke-Uninstall; if (-not $Quiet) { Wait-AnyKey }; exit 0 }
if ($Install)   { Invoke-Install; exit 0 }

$Host.UI.RawUI.WindowTitle = 'Claude Code'
if ($Updated) {
    $HomeNotice = TF 'upd_done_notice' $AppVersion
    # после обновления освежаем профиль Windows Terminal установленной копии
    if ((Test-Path -LiteralPath $AppScript) -and (Get-Command wt.exe -ErrorAction SilentlyContinue)) { try { Write-Fragment } catch {} }
}
Init-Native
if ($Cfg.autoUpdate) { Start-UpdateCheck }
try {
    if (-not $ClaudeExe) { if (-not (Show-Missing)) { return } }
    if (-not $Cfg.firstRunDone) { Show-Settings -First; $Cfg.firstRunDone = $true; Save-Settings }
    Show-Home
} catch {
    # не закрываем окно молча: показываем, что случилось и что делать
    $crash = $_
    Input-Restore
    try {
        Clear-Screen; [Console]::CursorVisible = $true
        [Console]::WriteLine("`n  $Red$($G.Err)$R $Bold$Ivory$(T 'crash_title')$R`n")
        [Console]::WriteLine("  $Ivory$($crash.Exception.Message)$R")
        if ($crash.InvocationInfo) { [Console]::WriteLine("  $Dim$($crash.InvocationInfo.PositionMessage -replace "`n", "`n  ")$R") }
        [Console]::WriteLine("`n  $Text2$(T 'crash_hint')$R")
        try {
            Set-Clipboard -Value ("Claude Code Launcher v$AppVersion`r`n$($crash.Exception.Message)`r`n$($crash.InvocationInfo.PositionMessage)`r`n$($crash.ScriptStackTrace)")
            [Console]::WriteLine("  $Dim$(T 'crash_copied')$R")
        } catch {}
        Wait-AnyKey
    } catch {}
} finally {
    Input-Restore
    [Console]::CursorVisible = $true
    Clear-Screen
}
