# Политика использования Claude Code Launcher

*Действует с 23 ноября 2026 г. English version below.*

## 1. Что это

Claude Code Launcher — бесплатная программа-меню для запуска [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) в Windows. Её поддерживает организация [20launcher25](https://github.com/20launcher25).

Лаунчер — **неофициальный** проект. Он не создан, не проверен и не поддерживается компанией Anthropic. «Claude» и «Claude Code» — товарные знаки Anthropic, они упоминаются только для того, чтобы назвать программу, с которой работает лаунчер.

## 2. Условия использования

- Лаунчером можно пользоваться бесплатно, лично и в работе.
- Работа с Claude Code через лаунчер остаётся работой с Claude Code: для неё действуют [условия Anthropic](https://www.anthropic.com/legal) и [правила использования](https://www.anthropic.com/legal/aup). Лаунчер их не меняет и не обходит. Лимиты подписки он только показывает и никак не увеличивает.
- Запрещено пользоваться лаунчером или его скиллами для действий, нарушающих закон или правила Anthropic.
- Делиться лаунчером можно ссылкой на этот репозиторий. Изменённые копии не выдавайте за официальную версию от 20launcher25 и не распространяйте под тем же названием.

## 3. Какие данные он использует

Лаунчер работает на вашем компьютере и **ничего о вас не отправляет**. Аналитики и телеметрии в нём нет.

| Что | Зачем | Куда уходит |
| --- | --- | --- |
| История сессий Claude Code (`~/.claude/projects`) | список недавних проектов и сессий | никуда, только чтение |
| Данные аккаунта из `~/.claude.json` (имя, почта, план) | экран «Сведения и лимиты» | никуда, только чтение |
| Лимиты подписки (файл пишет мод `usage-mod`) | полоски лимитов | никуда |
| Настройки лаунчера (`%LOCALAPPDATA%\ClaudeCodeLauncher`) | ваши настройки | никуда |

В интернет лаунчер обращается только сам: скачивает `manifest.json`, обновления и скиллы из этого репозитория (`raw.githubusercontent.com`). Как и любой сайт, GitHub видит при этом ваш IP-адрес. Автопроверку можно отключить: «Настройки → Проверять при запуске».

## 4. Обновления и скиллы

- Перед установкой каждый файл обновления или скилла сверяется с контрольной суммой SHA-256 из `manifest.json`, а файлы вне папки лаунчера и папки скилла не записываются.
- Скиллы из каталога — это инструкции для Claude. Устанавливая скилл, вы разрешаете Claude ими пользоваться. Прежде чем ставить скилл, прочитайте его описание.
- Изменения в репозиторий вносят только сопровождающие. Предложения от других людей принимаются через pull request после проверки (см. раздел 6).

## 5. Ответственность

Программа предоставляется **«как есть»**, без гарантий. Сопровождающие не отвечают за потерю данных, расход лимитов подписки или последствия действий Claude, запущенного через лаунчер. Режимы разрешений, которые позволяют Claude действовать без вопросов («сам правит файлы», «авто»), вы включаете под свою ответственность.

## 6. Как предложить изменение или сообщить о проблеме

- Ошибки и идеи пишите в [Issues](https://github.com/20launcher25/20launcher25/issues). К сообщению приложите отчёт: «Настройки → Проверка компонентов → Скопировать отчёт». В нём нет ничего, кроме версий и путей к файлам. Перед отправкой всё равно прочитайте его.
- Чтобы предложить код или скилл, сделайте fork и откройте pull request. В ветку `main` он попадёт только после одобрения сопровождающего.
- Об уязвимостях не пишите публично в Issues: воспользуйтесь [Security → Report a vulnerability](https://github.com/20launcher25/20launcher25/security).

## 7. Изменения политики

Новая версия политики публикуется в этом файле. Изменения видны в истории коммитов. Если вы продолжаете пользоваться лаунчером после изменения, значит, вы согласны с новой версией.

---

# Claude Code Launcher usage policy (English)

*Effective November 23, 2026.*

1. **What it is.** A free menu for starting Claude Code on Windows, maintained by [20launcher25](https://github.com/20launcher25). It is an **unofficial** project, not made, reviewed or supported by Anthropic. "Claude" and "Claude Code" are Anthropic trademarks, used only to name the program the launcher works with.
2. **Terms.** Free for personal and work use. Using Claude Code through the launcher is still subject to [Anthropic's terms](https://www.anthropic.com/legal) and [usage policy](https://www.anthropic.com/legal/aup). The launcher neither changes nor bypasses them and never raises subscription limits. Do not use it or its skills for unlawful activity. Share it by linking to this repository, and do not present modified copies as the official 20launcher25 version.
3. **Data.** Everything runs locally. The launcher sends no data about you and has no analytics or telemetry. It reads your Claude Code session history, account info from `~/.claude.json`, and limit data only to show them on screen. Its only network traffic is downloading `manifest.json`, updates and skills from this repository. As with any website, GitHub sees your IP address. Automatic checks can be turned off in Settings.
4. **Updates and skills.** Every downloaded file is checked against the SHA-256 in `manifest.json`, and files are never written outside the launcher or skill folder. Skills are instructions for Claude, so read a skill's description before installing it. Only maintainers change the repository. Other contributions go through reviewed pull requests.
5. **Liability.** Provided **"as is"**, without warranty. The maintainers are not liable for data loss, used-up subscription limits, or the results of actions taken by Claude. Permission modes that let Claude act without asking are your responsibility.
6. **Contributing and reporting.** Report bugs in [Issues](https://github.com/20launcher25/20launcher25/issues) and attach the report from "Settings → Component check → Copy report", reading it first. Propose code or skills through a fork and a pull request; they reach `main` only after a maintainer approves them. Report vulnerabilities privately via [Security → Report a vulnerability](https://github.com/20launcher25/20launcher25/security).
7. **Changes.** Policy updates are published in this file and visible in the commit history. Continuing to use the launcher after a change means you accept the new version.
