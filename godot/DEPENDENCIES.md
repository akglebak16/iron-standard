# Возможные зависимости Godot

Это кандидаты, не установленные в проект. Перед подключением фиксировать версию, проверять совместимость с закреплённой Godot 4.7.2 и сохранять текст лицензии в репозитории.

| Задача | Кандидат | Лицензия и решение |
| --- | --- | --- |
| Рост набора тестов | [GUT 9.7.x](https://github.com/bitwes/Gut/releases) | [MIT](https://github.com/bitwes/Gut); версия 9.7 заявляет поддержку Godot 4.7. Оценить, когда собственный тестовый запуск станет тесен. |
| Разветвлённые диалоги | [Dialogue Manager 4](https://github.com/nathanhoad/godot_dialogue_manager) | MIT; пробовать при переносе диалогов. [Публикация в Asset Store](https://store.godotengine.org/asset/nathanhoad/dialogue-manager/) отмечена нестабильной, поэтому сначала отдельная проверка совместимости. |
| Steam API | [GodotSteam GDExtension](https://store.godotengine.org/asset/godotsteam/godotsteam-gdextension/) | MIT; рассматривать ближе к Steam-сборке с обычными шаблонами экспорта Godot. |

Локализация, сохранения и звук, создаваемый кодом, пока не требуют сторонних библиотек: у Godot есть [переводы CSV/PO](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html), [FileAccess и JSON](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html), [AudioStreamGenerator](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html). Эти варианты бесплатны для коммерческой игры. Публикация в Steam отдельно требует [взнос Steam Direct](https://partner.steamgames.com/doc/gettingstarted/appfee); он не связан с лицензиями плагинов.
