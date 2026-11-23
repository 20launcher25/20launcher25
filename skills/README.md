# Каталог скиллов

Каждая папка здесь с файлом `SKILL.md` попадает в каталог «Настройки → Установить скиллы» лаунчера.

```
skills/
  my-skill/
    SKILL.md        # frontmatter: name, description
    ...             # любые дополнительные файлы скилла
```

Имя папки = имя скилла (латиница, цифры, `.`, `_`, `-`). Описание в каталоге берётся из поля
`description` во frontmatter `SKILL.md`.

После добавления или правки скилла пересоберите манифест и закоммитьте:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Make-Manifest.ps1
```
