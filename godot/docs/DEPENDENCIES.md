# Зависимости и инструменты

Закреплённый движок — Godot 4.7.2, Windows x64, Compatibility renderer.
Проект использует GDScript и пакетный GDExtension для вычисления контактов.
Граница native-ядра описана в [ADR-011](architecture/ADR-011-native-contacts.md).

Версии, URL и SHA256 portable LLVM-mingw, Python и godot-cpp закреплены в
`tools/native_dependencies.json`. Установка: `pwsh -File godot/tools/native_bootstrap.ps1`
из корня репозитория. Зависимости остаются внутри `dist/godot/native-tools`,
системная установка не требуется. `tools/native_build.cjs` собирает DLL;
test/release runner вызывает его автоматически.

Тексты лицензий находятся в `adapters/godot/native/licenses/` и включаются
в экспорт. Новая внешняя библиотека требует закреплённой версии, проверки
совместимости и сохранённой лицензии. Прежний список кандидатов не является
решением об их подключении.
