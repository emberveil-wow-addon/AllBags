# AllBags

**Русский** · [English](#english)

Все сумки в одном окне для клиента Emberveil (WoW 1.12.1).

Вместо пяти отдельных окон — одна сетка со всем содержимым рюкзака и сумок.

## Возможности

- **Одно окно** на все сумки, ширина сетки настраивается от 4 до 20 столбцов
- **Сортировка по качеству** — ряды заполняются сверху, пустые слоты уходят вниз. Сортировка виртуальная: предметы в сумках не перекладываются, меняется только порядок показа
- **Рамки качества** — необычное и выше подсвечивается цветом
- **Полное взаимодействие** — ЛКМ взять или положить, ПКМ использовать, надеть, продать или убрать в банк, Shift и ЛКМ разделить стопку, подсказки при наведении
- **Деньги и свободное место** в нижней строке
- **Кнопка отключения** возвращает штатные окна сумок, не выгружая аддон

## Как открывается

Аддон перехватывает штатные функции открытия сумок, поэтому работает любая клавиша, которая уже назначена на сумки, клик по кнопке сумки и автооткрытие у торговца. Своя команда — /bags

## Управление

- **Правая кнопка по рамке окна** — меню со всеми настройками
- **Левая кнопка** — перетаскивание, положение запоминается

| Команда | Действие |
|---|---|
| /bags | Открыть или закрыть окно |
| /bags menu | Меню |
| /bags sort | Переключить сортировку |
| /bags cols N | Столбцов в ряду, от 4 до 20 |
| /bags border N | Толщина окантовки окна, от 2 до 24 |
| /bags lang ru, en, auto | Язык |
| /bags off, on | Отключить или включить перехват сумок |
| /bags reset | Вернуть окно на место |

## Установка

Распакуйте папку AllBags в Interface/AddOns/

---

## English

All bags in one window for the Emberveil client (WoW 1.12.1). Instead of five separate windows, a single grid with everything in your backpack and bags.

### Features

- **One window** for every bag, grid width configurable from 4 to 20 columns
- **Sort by quality** — rows fill from the top, empty slots go last. The sort is virtual: nothing is moved inside your bags, only the display order changes
- **Quality borders** — uncommon and above are highlighted
- **Full interaction** — left click to pick up or drop, right click to use, equip, sell or bank, Shift and left click to split a stack, tooltips on hover
- **Money and free space** in the footer
- **Disable button** brings back the default bag windows without unloading the addon

### How it opens

The addon hooks the default bag opening functions, so whatever key is already bound to bags works, as does clicking a bag button and the merchant auto-open. Its own command is /bags

### Usage

- **Right click the window frame** for the settings menu
- **Left click** to drag it, the position is remembered

| Command | Action |
|---|---|
| /bags | Open or close the window |
| /bags menu | Menu |
| /bags sort | Toggle sorting |
| /bags cols N | Columns per row, 4 to 20 |
| /bags border N | Window border thickness, 2 to 24 |
| /bags lang ru, en, auto | Language |
| /bags off, on | Disable or enable the bag hooks |
| /bags reset | Move the window back |

### Installation

Unpack the AllBags folder into Interface/AddOns/

---

## Лицензия / License

MIT
