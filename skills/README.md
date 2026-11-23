# Каталог скиллов

**Русский** · [Қазақша](#қазақша) · [English](#english)

Эти скиллы ставятся в `~/.claude/skills` из лаунчера: «Настройки → Установить скиллы». Claude Code увидит новый скилл в следующей сессии.

| Скилл | Для чего | Автор | Лицензия |
| :-- | :-- | :-- | :-- |
| [humanize](humanize) | очеловечить текст на русском и английском, убрать следы ИИ | 20launcher25 | |
| [humanize-kk](humanize-kk) | то же для казахского: отчёты по практике, курсовые, рефераты | 20launcher25 | |
| [landing-page-design](landing-page-design) | лендинги: структура, тексты, вёрстка, конверсия | 20launcher25 | |
| [pitch-deck-advisor](pitch-deck-advisor) | питч-деки для инвесторов: сборка и разбор | 20launcher25 | |
| [figma-designer](figma-designer) | дизайн в Figma на переменных, стилях и компонентах | 20launcher25 | |
| [skill-inspector](skill-inspector) | проверить чужой скилл перед установкой | 20launcher25 | |
| [frontend-design](frontend-design) | выразительный дизайн интерфейсов без шаблонности | Anthropic | Apache 2.0 |
| [unslop](unslop) | превратить «нейросетевой» интерфейс в продуманный | Damir Sokolovsky | CC BY 4.0 |
| [ui-ux-pro-max](ui-ux-pro-max) | база палитр, шрифтов и стилей с поиском | Next Level Builder | MIT |
| [agent-browser](agent-browser) | управление браузером из командной строки | Vercel | Apache 2.0 |
| [supabase](supabase) | всё про Supabase: база, авторизация, функции, хранилище | Supabase | MIT |
| [supabase-postgres-best-practices](supabase-postgres-best-practices) | правила для Postgres: схемы, индексы, RLS, производительность | Supabase | MIT |
| [adaptive](adaptive) | Android-интерфейсы под телефоны, планшеты, складные устройства | Google | Apache 2.0 |
| [agp-9-upgrade](agp-9-upgrade) | переход Android-проекта на AGP 9 | Google | Apache 2.0 |
| [jetpack-compose-performance](jetpack-compose-performance) | ускорение Jetpack Compose | Google | Apache 2.0 |
| [compose-expert](compose-expert) | Jetpack Compose и Compose Multiplatform | Adit Lal | MIT |
| [configuring-r8-for-compose](configuring-r8-for-compose) | настройка R8 для Compose | Jaewoong Eum (skydoves) | Apache 2.0 |

Чужие скиллы лежат здесь без изменений, вместе с файлами лицензий их авторов. Единственная правка: в `ui-ux-pro-max` путь к скрипту поиска заменён на `~/.claude/skills/ui-ux-pro-max/scripts/search.py`, чтобы он работал на любом компьютере.

`ppt-master` (автор Hugo He, MIT) в каталог не вошёл: в нём около 13 тысяч файлов шаблонов, и лаунчеру пришлось бы скачивать их по одному. Его удобнее ставить из оригинального репозитория.

## Как добавить скилл

```
skills/
  my-skill/
    SKILL.md        # frontmatter: name, description
    ...             # любые дополнительные файлы скилла
```

1. Имя папки становится именем скилла: латиница, цифры, `.`, `_`, `-`.
2. Описание в каталоге берётся из поля `description` во frontmatter `SKILL.md`.
3. Если скилл чужой, положите рядом файл лицензии автора и проверьте, что она разрешает распространение.
4. Уберите из файлов пути со своего компьютера, почту, ключи и токены.
5. Пересоберите манифест и откройте pull request:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Make-Manifest.ps1
```

---

## Қазақша

Бұл скиллдер лаунчерден `~/.claude/skills` қалтасына орнатылады: «Баптаулар → Скиллдерді орнату». Claude Code жаңа скиллді келесі сессияда көреді. Бөгде авторлардың скиллдері өзгертусіз, лицензия файлдарымен бірге сақталған. Жаңа скилл қосу үшін `skills/<атауы>/SKILL.md` қалтасын жасап, манифестті қайта жинаңыз да, pull request ашыңыз.

## English

These skills install into `~/.claude/skills` from the launcher: Settings → Install skills. Claude Code picks up a new skill in the next session. Third-party skills are kept unchanged, together with their authors' license files. To add a skill, create `skills/<name>/SKILL.md`, rebuild the manifest and open a pull request.
