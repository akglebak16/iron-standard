/* ================= карта мира ================= */
/* Версия карты: 1 — старая (2600×1700, три фракции), 2 — Европа (5200×3400, пять фракций). Версия лежит в G.mapv.
   У старых сохранений и у мира сервера её нет: тогда её видно по поселениям (в старом мире все они внутри 2600×1700),
   так старые игры продолжаются на старой карте, а новые идут на Европе. */
const MAP_SIZE = { 1: [2600, 1700], 2: [5200, 3400], 3: [5200, 3400], 4: [5200, 3400] }, GC = 20, DEFAULT_MAPV = 4; // DEFAULT_MAPV — на какой карте начинаются новые игры
let WW = MAP_SIZE[DEFAULT_MAPV][0], WH = MAP_SIZE[DEFAULT_MAPV][1], GW = WW / GC, GH = Math.ceil(WH / GC);
function mapVer() { if (G && G.mapv) return G.mapv; if (G && G.settles && G.settles.length) return G.settles.some(s => s.fac === 'pact') ? 4 : G.settles.some(s => s.fac === 'dom') ? 3 : G.settles.some(s => s.x > MAP_SIZE[1][0] || s.y > MAP_SIZE[1][1]) ? 2 : 1; return DEFAULT_MAPV; }
const isEU = () => mapVer() >= 2; // карта Европы (версии 2 и 3)
function setMapSize(v) { WW = MAP_SIZE[v][0]; WH = MAP_SIZE[v][1]; GW = WW / GC; GH = Math.ceil(WH / GC); PA.g = new Float32Array(GW * GH); PA.prev = new Int32Array(GW * GH); PA.closed = new Uint8Array(GW * GH); }
let G = null, WT = null; // G — состояние игры, WT — статичный ландшафт
const SNAMES = {
  nord: { town: ['Хольмгард', 'Скьярвик'], castle: ['Ульвхейм', 'Бьёрнборг'], village: ['Эйдфьорд', 'Ватнсдал', 'Ормслунд', 'Хавик', 'Тюрсби'] },
  emp: { town: ['Вентум', 'Мариум'], castle: ['Кастра Руфа', 'Корвинум'], village: ['Остра', 'Тибурий', 'Сильва', 'Агрум', 'Лукрин'] },
  khan: { town: ['Кешир', 'Алтын-Тобе'], castle: ['Булан-Орда', 'Тенгри-Кала'], village: ['Ак-Булак', 'Сары-Агач', 'Темир-Тау', 'Ордабаш', 'Кара-Су'] }
};
const CAMPN = ['Волчья яма', 'Разбитая башня', 'Чёрный брод', 'Пещера висельников', 'Гнилой овраг', 'Старая застава'];
const WAR = { nord: { emp: 1, kin: 1, dom: 1 }, emp: { nord: 1, khan: 1, emi: 1, pact: 1 }, khan: { emp: 1, dom: 1 }, kin: { emi: 1, nord: 1, pact: 1 }, emi: { kin: 1, emp: 1 }, dom: { khan: 1, nord: 1, pact: 1 }, pact: { kin: 1, dom: 1, emp: 1 }, bandit: { nord: 1, emp: 1, khan: 1, kin: 1, emi: 1, dom: 1, pact: 1 } };
const FAC_V = { 1: ['nord', 'emp', 'khan'], 2: ['nord', 'emp', 'khan', 'kin', 'emi'], 3: ['nord', 'emp', 'khan', 'kin', 'emi', 'dom'], 4: ['nord', 'emp', 'khan', 'kin', 'emi', 'dom', 'pact'] }; // какие фракции есть на карте версий 1–4
const worldF = () => FAC_V[G ? mapVer() : DEFAULT_MAPV];
const atWar = (a, b) => a !== b && (G && G.wars && a !== 'bandit' && b !== 'bandit' ? !!G.wars[a < b ? a + '|' + b : b + '|' + a] : ((WAR[a] && WAR[a][b]) || (WAR[b] && WAR[b][a]))); // в одиночной игре войны живые (05g_war.js)
const TCOST = [0, 1, 1.75, 1.5, 0];
const TNAME = ['вода', 'равнина', 'лес', 'холмы', 'горы', 'река'];

function genWorld(seed) { const v = mapVer(); if (G) G.mapv = v; setMapSize(v); return v === 1 ? genWorldV1(seed) : genWorldV2(seed); }
/* ---------- Европа: карта версии 2 ----------
   Берега нарисованы по долготе и широте (примерно), шум делает береговую линию живой.
   Проекция: долгота −14…56°, широта 31…66° → 5200×3400. Мелкие острова — просто красота (корабли в игре не плавают),
   а Британия соединена с материком узким перешейком у Дувра, Дания — цепочкой проливов. */
const EU = { lon0: -14, lon1: 56, lat0: 31, lat1: 66 };
const euX = lon => (lon - EU.lon0) / (EU.lon1 - EU.lon0) * WW, euY = lat => (EU.lat1 - lat) / (EU.lat1 - EU.lat0) * WH;
const euLon = x => EU.lon0 + x / WW * (EU.lon1 - EU.lon0), euLat = y => EU.lat1 - y / WH * (EU.lat1 - EU.lat0);
// [1 — суша, 0 — море, долгота, широта, ...]. Фигуры рисуются по порядку: материк, потом моря вырезаются, потом острова поверх
const EU_SHAPES = [
  [1, -11, 28, -9.7, 30.4, -9.8, 31.5, -8.8, 32.8, -7.6, 33.6, -6.8, 34.1, -6.2, 35.2, -5.9, 35.8, -5.6, 36, -6.3, 36.5, -6.9, 37.2, -7.5, 37.2, -7.9, 37, -8.9, 37, -8.8, 37.9, -8.9, 38.5, -9.5, 38.8, -9.4, 39.4, -8.9, 40.2, -8.7, 41.1, -8.9, 42, -9.3, 42.9, -8.4, 43.4, -7.9, 43.8, -5.7, 43.6, -3.8, 43.5, -2.9, 43.4, -1.8, 43.4, -1.4, 44, -1.25, 44.7, -1.1, 45.5, -1.2, 46.1, -1.8, 46.5, -2.2, 47.25, -3.1, 47.5, -3.4, 47.7, -4.7, 48, -4.7, 48.4, -4.5, 48.7, -3.5, 48.8, -3, 48.85, -2, 48.65, -1.5, 48.65, -1.6, 48.85, -1.8, 49.4, -1.95, 49.7, -1.6, 49.65, -1.25, 49.7, -1.2, 49.4, -.5, 49.35, -.25, 49.3, .2, 49.4, .2, 49.7, 1.1, 49.9, 1.55, 50.2, 1.6, 50.85, 1.85, 50.97, 2.4, 51.05, 2.9, 51.2, 3.6, 51.4, 3.8, 51.6, 4.1, 52, 4.7, 52.95, 5.5, 53.35, 6.5, 53.4, 7.2, 53.35, 8.1, 53.55, 8.9, 53.9, 8.8, 54.5, 8.4, 54.9, 8.3, 55.5, 8.1, 56, 8.2, 56.7, 8.6, 57.1, 10.6, 57.75, 10.5, 57.4, 10.4, 57, 10.9, 56.4, 10.25, 56.15, 9.9, 55.85, 9.5, 55.5, 9.4, 55, 9.4, 54.8, 10.15, 54.35, 11.1, 54.4, 10.9, 53.95, 11.4, 54, 12.1, 54.2, 12.5, 54.45, 13.4, 54.6, 14, 54, 14.3, 53.9, 15.5, 54.2, 17.5, 54.75, 18.6, 54.75, 18.7, 54.35, 19.8, 54.4, 20.4, 54.95, 21.1, 55.3, 21.1, 55.7, 21, 56.5, 21.5, 57.4, 22.6, 57.75, 23.5, 57.2, 24.1, 57, 24.4, 57.6, 24.5, 58.35, 23.5, 58.9, 24.7, 59.45, 28, 59.5, 30.2, 59.95, 28.7, 60.7, 27, 60.4, 25, 60.15, 23, 59.8, 22.2, 60.4, 21.4, 61.5, 21.6, 63.1, 25.4, 65, 24.5, 65.75, 24.5, 67.5, 60, 67.5, 60, 28],
  // Средиземное море (с Адриатикой, Эгейским и Левантом)
  [0, -5, 36, -4.9, 36.5, -4.4, 36.65, -2.45, 36.8, -2.1, 36.72, -.95, 37.55, -.5, 38.3, .2, 38.7, -.3, 39.45, 0, 40, .9, 40.7, 1.25, 41.1, 2.2, 41.4, 3.1, 41.85, 3.3, 42.3, 3.05, 42.7, 3.2, 43.15, 3.7, 43.4, 4.2, 43.5, 4.7, 43.4, 5.35, 43.3, 5.9, 43.1, 6.8, 43.4, 7.3, 43.7, 7.6, 43.8, 8.9, 44.4, 9.8, 44.1, 10.2, 43.9, 10.3, 43.55, 10.5, 42.95, 11.1, 42.4, 11.8, 42.1, 12.2, 41.8, 12.6, 41.45, 13.6, 41.2, 14.25, 40.85, 14.35, 40.6, 14.8, 40.65, 15, 40.35, 15.3, 40, 15.7, 39.95, 16, 39.35, 15.85, 38.6, 15.7, 38.25, 15.65, 38.1, 16.05, 37.95, 16.3, 38.3, 16.6, 38.8, 17.15, 39.1, 16.65, 39.6, 16.5, 39.75, 17.2, 40.45, 17.95, 40.05, 18.35, 39.8, 18.5, 40.15, 17.95, 40.65, 17.3, 40.95, 16.85, 41.15, 16, 41.6, 16.2, 41.95, 15, 42, 14.2, 42.45, 13.5, 43.6, 12.9, 43.9, 12.6, 44.05, 12.3, 44.4, 12.5, 44.95, 12.35, 45.4, 13.75, 45.65, 13.85, 44.85, 14.4, 45.3, 15.2, 44.1, 15.9, 43.7, 16.45, 43.5, 18.1, 42.65, 18.7, 42.4, 19.1, 42.1, 19.45, 41.3, 19.45, 40.45, 20, 39.85, 20.25, 39.5, 20.75, 38.95, 21.4, 38.35, 21.75, 38.25, 21.1, 37.9, 21.3, 37.65, 21.65, 36.9, 22.45, 36.4, 22.57, 36.75, 23.05, 36.7, 22.8, 37.55, 23, 37.9, 23.65, 37.95, 24, 37.65, 24, 38, 23.6, 38.45, 22.95, 39.35, 22.6, 40.2, 22.95, 40.6, 23.7, 40.2, 24.35, 40.1, 24.4, 40.9, 25.9, 40.85, 26.05, 40.7, 26.2, 40.05, 26.4, 40.15, 26.05, 39.5, 26.7, 39.3, 26.9, 39.1, 27.1, 38.4, 27.25, 37.85, 27.6, 37.25, 27.4, 37, 28.3, 36.8, 29.1, 36.65, 29.6, 36.2, 30.7, 36.85, 32, 36.55, 32.8, 36.05, 34.6, 36.75, 36.15, 36.6, 35.8, 35.5, 35.9, 34.9, 35.5, 33.9, 35, 32.8, 34.75, 32.05, 34.4, 31.5, 32.3, 31.25, 29.9, 31.2, 27.2, 31.4, 25.2, 31.6, 24, 32.1, 22.7, 32.8, 21.9, 33, 20.1, 32.1, 19.3, 30.9, 18, 29.5, 16.6, 31.2, 15.1, 32.4, 13.2, 32.9, 12.1, 33.1, 10.1, 33.9, 10.8, 34.7, 10.6, 35.8, 10.6, 36.4, 11.1, 37.1, 10.3, 36.8, 9.9, 37.3, 8.8, 37, 7.8, 36.9, 6.9, 36.9, 5.1, 36.75, 3, 36.8, 1.3, 36.5, -.65, 35.75, -1.4, 35.3, -2.95, 35.3, -3.9, 35.2, -5.1, 35.6],
  // Чёрное море, Азовское и Мраморное
  [0, 29.2, 41.2, 28.3, 41.5, 28, 41.95, 27.5, 42.5, 27.95, 43.2, 28.6, 43.8, 28.65, 44.2, 29.7, 45.2, 30.3, 46, 30.75, 46.5, 31.7, 46.6, 32.5, 46.55, 33, 46.2, 33.9, 46.05, 33, 45.65, 32.55, 45.35, 33.4, 45.1, 33.5, 44.6, 34, 44.4, 35.4, 45.05, 36.5, 45.35, 36.75, 45.2, 37.3, 44.9, 37.8, 44.7, 39.1, 44.1, 39.7, 43.6, 41, 43, 41.65, 42.15, 41.6, 41.6, 39.7, 41, 38.4, 40.95, 36.3, 41.3, 35.15, 42, 33.8, 41.97, 31.8, 41.45, 29.6, 41.2],
  [0, 35.2, 45.75, 35, 46.3, 36, 46.65, 37, 46.9, 37.8, 47.1, 38.9, 47.2, 38.4, 46.6, 37.9, 46, 37.2, 45.5, 36.7, 45.4, 36, 45.5],
  [0, 27, 40.45, 28, 40.35, 29, 40.4, 29.5, 40.75, 28.9, 40.95, 28, 40.98, 27.2, 40.7],
  // Каспий
  [0, 47.7, 46.2, 49, 46.6, 51, 47, 53, 46.6, 53.4, 45, 51.2, 44.5, 50.4, 43.4, 51.3, 42.2, 52.9, 41.6, 53.8, 40, 53.9, 38.3, 52.5, 36.9, 50.5, 36.9, 49, 37.7, 49, 38.6, 49.4, 40.3, 48.9, 41.2, 47.7, 43, 47, 44.4, 47.4, 45.4],
  // Скандинавия
  [1, 14, 67.5, 13, 66, 12.2, 65.4, 11.5, 64.6, 10, 64, 8.8, 63.7, 7.7, 63.1, 6.1, 62.5, 5.1, 62.2, 4.9, 61, 5, 60.4, 5.2, 59.4, 5.6, 58.9, 6, 58.4, 7.05, 58, 8, 58.1, 8.8, 58.4, 10, 59, 10.6, 59.15, 11.2, 58.9, 11.9, 57.7, 12.8, 56.7, 12.7, 56.05, 13, 55.55, 13.8, 55.4, 14.35, 55.55, 14.8, 56.15, 15.6, 56.15, 16.4, 56.7, 16.65, 57.75, 16.6, 58.3, 16.7, 58.65, 17.95, 58.9, 18.1, 59.35, 18.9, 59.9, 17.2, 60.7, 17.1, 61.7, 17.3, 62.4, 18.7, 63.3, 20.3, 63.8, 21, 64.7, 22.1, 65.55, 24, 65.75, 26, 66.2, 26, 67.5],
  // Датские острова и проливы между ними
  [1, 9.7, 55.35, 10, 55.62, 10.6, 55.62, 10.95, 55.35, 10.7, 55.05, 10.1, 55.05],
  [1, 11.1, 55.6, 11.4, 56, 12.2, 56.1, 12.6, 55.9, 12.75, 55.4, 12.2, 55.1, 11.5, 55.2],
  [1, 9.6, 55.3, 10.2, 55.3, 10.2, 55.7, 9.6, 55.7], [1, 10.7, 55.25, 11.3, 55.25, 11.3, 55.7, 10.7, 55.7], [1, 12.4, 55.45, 13.1, 55.45, 13.1, 55.85, 12.4, 55.85],
  // Британия, перешеек у Дувра, Ирландия
  [1, -5.7, 50.1, -4.2, 50.3, -3, 50.7, -1.9, 50.7, -1.1, 50.8, .3, 50.8, 1.4, 51.1, 1.4, 51.4, .8, 51.5, 1.2, 51.8, 1.7, 52.5, 1.7, 52.9, .3, 52.9, .2, 53.5, -.1, 53.7, -.4, 54.1, -1.2, 54.6, -1.5, 55, -1.6, 55.6, -2.2, 56, -3, 56, -2.5, 56.4, -2, 57, -1.8, 57.5, -3, 57.7, -4, 57.6, -3.1, 58.5, -3, 58.7, -5, 58.6, -5.4, 57.8, -5.8, 57.3, -5.6, 56.5, -5.6, 56, -5.7, 55.3, -4.9, 55.7, -4.7, 55, -5.1, 54.8, -3.4, 54.9, -3.2, 54.4, -3.1, 53.9, -3.1, 53.4, -3.8, 53.3, -4.6, 53.3, -4.7, 52.8, -4.1, 52.5, -4.9, 52.1, -5.2, 51.9, -4.3, 51.7, -3.2, 51.5, -2.7, 51.6, -3.5, 51.2, -4.2, 51.1, -5, 50.5],
  [1, 1.1, 50.9, 2.1, 50.9, 2.1, 51.4, 1.1, 51.4],
  [1, -6, 52.2, -6.1, 53.3, -6, 54, -5.5, 54.5, -6.2, 55.2, -7.2, 55.3, -8.5, 54.8, -8.8, 54.2, -10, 54.2, -9.9, 53.3, -9.5, 52.7, -10.4, 52.1, -9.6, 51.5, -8.3, 51.8, -7, 52.1],
  // Сицилия (с мостиком у Мессины), Сардиния, Корсика, Крит, Кипр, Мальорка, Готланд
  [1, 12.45, 37.9, 13.3, 38.2, 14, 38.05, 15.2, 38.3, 15.6, 38.25, 15.1, 37.2, 15.1, 36.7, 14.4, 36.75, 13, 37.1, 12.45, 37.6], [1, 15.4, 37.95, 15.95, 37.95, 15.95, 38.3, 15.4, 38.3],
  [1, 8.2, 40.9, 8.4, 41.2, 9.2, 41.25, 9.7, 40.9, 9.8, 40, 9.6, 39.2, 9, 38.9, 8.4, 39, 8.4, 39.9],
  [1, 8.6, 42.4, 9.3, 43, 9.5, 42.6, 9.4, 41.8, 9.1, 41.4, 8.7, 41.7, 8.6, 42],
  [1, 23.5, 35.4, 24.5, 35.7, 25.7, 35.5, 26.3, 35.25, 25.5, 34.9, 24, 35],
  [1, 32.3, 34.9, 33, 35.4, 34, 35.7, 34.6, 35.75, 34, 35, 33, 34.6],
  [1, 2.4, 39.55, 3, 39.95, 3.5, 39.75, 3.1, 39.3, 2.6, 39.4], [1, 18.1, 57.1, 18.6, 57.9, 19.2, 57.5, 18.8, 57]
];
// Горные хребты: [ширина, долгота, широта, ...]
const EU_RIDGES = [
  [70, 6.8, 44.2, 7, 45.3, 8, 46, 9.5, 46.5, 11.5, 46.7, 13.5, 46.6, 15.5, 47],                      // Альпы
  [45, -1.7, 43.2, 0, 42.7, 1.5, 42.5, 3, 42.45],                                                    // Пиренеи
  [38, -8, 42.9, -5, 43, -2.5, 42.9], [34, -5.5, 36.9, -3.5, 37, -1.8, 37.4], [28, -6, 40.3, -4, 40.8, -3.2, 41], [26, -6, 38.2, -3, 38.3],
  [38, 8.8, 44.4, 10.5, 44.1, 12, 43.4, 13.5, 42.3, 14.5, 41.5, 15.8, 40.2, 16.2, 39, 16, 38.2],     // Апеннины
  [45, 14, 45.5, 16, 44.3, 18, 43.3, 19.8, 42.3, 20.5, 41.3, 21, 40.2, 21.8, 38.9],                  // Динарские горы и Пинд
  [40, 22.5, 43.4, 25, 42.8, 27.5, 42.8], [32, 24, 41.7, 26, 41.5],                                  // Балканы и Родопы
  [55, 17.5, 49.2, 19.5, 49.4, 22, 49, 24.5, 48.2, 25.5, 47.2, 25.5, 46, 24, 45.5, 22.5, 45.3, 21.8, 44.6], // Карпаты
  [28, 12.5, 50.4, 15, 50.7, 17, 50.3], [26, 7.7, 47.8, 8.2, 48.8], [38, 2.5, 45.5, 3.5, 44.8], [26, 5.8, 46.8, 6.5, 46.2],
  [65, 6, 60, 7.5, 61.3, 9, 62.3, 11, 63.7, 13, 65, 15, 66.2],                                       // Скандинавские горы
  [30, -5.4, 57.2, -4.2, 56.9, -3.5, 57.1], [25, -2.3, 53.5, -2.2, 54.8], [28, -4, 52.5, -3.6, 53],  // Британия
  [55, 37.5, 44.2, 40, 43.4, 42.5, 42.9, 45, 42.2, 47.5, 41.8, 48.5, 41.2],                          // Кавказ
  [28, 31, 41.1, 35.5, 41.3, 39, 40.8, 41.5, 40.7], [42, 30, 37, 33, 36.8, 36, 37.5, 38.5, 38, 42, 37.5, 44, 37, 46, 35, 48.5, 33.5, 51, 32], [35, 49.5, 36.5, 52.5, 36.2, 55.5, 36.5],
  [52, -9, 31.2, -5.5, 32, -2, 33.5, 1, 34.5, 4, 35, 7, 35.5, 9.5, 35.6]                              // Атлас
];
// Где живёт каждая фракция: столица [долгота, широта, rx, ry] и эллипсы, в которых лежат её земли
const EU_REG = {
  nord: { cap: [10.7, 59.7, .6, .5], discs: [[10.2, 60.2, 2.6, 1.7], [15.6, 59.4, 3, 1.6], [13.2, 57, 2, 1.3], [9.8, 56.3, 1.2, .9], [16.6, 62, 2.4, 1.2], [10.4, 63.3, 1.4, .7], [24.5, 61.5, 2.6, 1.3]] },
  kin: { cap: [2.4, 48.8, .7, .5], discs: [[2.4, 47.5, 4.2, 2.6], [-1.3, 52.6, 1.8, 2], [-3.5, 54.6, 1.3, 1.1], [5.2, 50.8, 1.6, 1.1], [-3.5, 42.9, 3.5, .7], [.8, 41.8, 1.5, .8]] },
  emp: { cap: [12.5, 42, .6, .5], discs: [[12.2, 42.8, 2.3, 2], [15.8, 40.6, 1.3, 1], [14, 37.6, .9, .45], [14.5, 47.4, 3, 1.1], [19.5, 47.2, 2.7, 1.1], [19.5, 43.8, 3.2, 2], [25, 42.7, 3, 1], [22.2, 39.2, 1.5, 1.6], [31.5, 39.2, 5, 1.5], [29, 41.1, 1.5, .5]] },
  khan: { cap: [32, 50, .9, .7], discs: [[36, 49.5, 4.5, 3.2], [47, 52, 6, 3.5], [27, 50.2, 2.4, 1.1], [41, 45.5, 3, 1.2], [52, 47.5, 3, 3]] },
  dom: { cap: [26.9, 54.9, .6, .5], discs: [[26.5, 54, 2.4, 1.3], [23.4, 54.4, 2.4, 1.4], [24.8, 57, 1.8, 1.2], [29.8, 53.4, 2.2, 1.4], [30.5, 56, 1.4, 1], [33.2, 54.8, 2.2, 1.4], [27.5, 51.6, 2, 1.1]] },
  pact: { cap: [21, 52.2, .6, .5], discs: [[21, 52, 2.2, 1.3], [17, 52.3, 2, 1.2], [19.8, 50.2, 1.8, .9], [13.4, 52.5, 2.4, 1.2], [10.5, 51.4, 2.6, 1.3], [11, 48.8, 2, 1], [9.5, 53.6, 1.6, .7], [18.6, 54.1, 1.4, .6], [8.8, 48.5, 1.6, .9], [14.4, 49.4, 1.7, .9]] },
  emi: { cap: [-5.6, 37.8, 1, .6], discs: [[-5.2, 37.6, 2.8, 1.1], [-6.5, 39.5, 1.5, .9], [-2.5, 39.2, 2.5, 1], [-5.5, 34.4, 2, 1.3], [-1.5, 35.4, 3.5, 1.2], [4.2, 36, 3.4, 1.3], [8.8, 35.8, 2.4, 1.3]] },
  wild: { discs: [[45, 58, 6, 3], [48, 34.5, 5, 1.5], [10, 33.2, 6, .8], [38, 55.5, 3, 1.3]] }
};
const SNAMES2 = {
  nord: { town: ['Хольмгард', 'Скьярвик', 'Нидарвик', 'Вестерхавн'], castle: ['Ульвхейм', 'Бьёрнборг', 'Драккенхольм'], village: ['Эйдфьорд', 'Ватнсдал', 'Ормслунд', 'Хавик', 'Тюрсби', 'Грюнвик', 'Скальбю', 'Фьялнес'] },
  emp: { town: ['Вентум', 'Мариум', 'Новус Портус', 'Аурелиум'], castle: ['Кастра Руфа', 'Корвинум', 'Кастра Нигра'], village: ['Остра', 'Тибурий', 'Сильва', 'Агрум', 'Лукрин', 'Пальма', 'Фонтана', 'Вилла Нова'] },
  khan: { town: ['Кешир', 'Алтын-Тобе', 'Сарай-Кала', 'Орда-Балык'], castle: ['Булан-Орда', 'Тенгри-Кала', 'Кызыл-Кала'], village: ['Ак-Булак', 'Сары-Агач', 'Темир-Тау', 'Ордабаш', 'Кара-Су', 'Жайлау', 'Узун-Кюль', 'Бай-Тал'] },
  kin: { town: ['Аржанкур', 'Сен-Люс', 'Бельмон', 'Вильнёв'], castle: ['Монфокон', 'Шато-Руж', 'Рокбрюн'], village: ['Лаж-Дюбуа', 'Бовуар', 'Сен-Реми', 'Ла-Форж', 'Пре-Верт', 'Мон-Клер', 'Фонтене', 'Круа-Бланш'] },
  dom: { town: ['Мядель', 'Новогрудок', 'Ковенск', 'Полоцк'], castle: ['Крево', 'Гольшаны', 'Мир'], village: ['Нарочь', 'Свирь', 'Кобыльник', 'Вишнев', 'Мстижь', 'Ляды', 'Богушевка', 'Дольск'] },
  pact: { town: ['Варшава', 'Познань', 'Краков', 'Берлин'], castle: ['Мальборк', 'Вавель', 'Вартбург'], village: ['Гнезно', 'Лович', 'Кутно', 'Плоцк', 'Радом', 'Калиш', 'Бранденбург', 'Любек'] },
  emi: { town: ['Аль-Захра', 'Мадинат-Нур', 'Баб-эш-Шамс', 'Рабат-Султан'], castle: ['Каср-эль-Хаджар', 'Калъат-Сакр', 'Хисн-аль-Асад'], village: ['Айн-Сафра', 'Вади-Рамль', 'Дар-эль-Хаджар', 'Сук-Тамар', 'Бир-Нахль', 'Тель-Асвад', 'Ксар-Ильм', 'Аль-Манара'] }
};
const CAMPN2 = ['Волчья яма', 'Разбитая башня', 'Чёрный брод', 'Пещера висельников', 'Гнилой овраг', 'Старая застава', 'Ущелье воронов', 'Заброшенная шахта', 'Костяной холм', 'Разорённый монастырь', 'Тёмная роща', 'Дозорная башня', 'Лисья нора', 'Каменная пасть'];

// закрасить многоугольник (чётно-нечётное правило) в сетке с шагом res; pts — x,y в единицах карты
function polyFill(m, W, H, res, pts, v) {
  const n = pts.length / 2; let y0 = 1e9, y1 = -1e9; for (let i = 1; i < pts.length; i += 2) { y0 = Math.min(y0, pts[i]); y1 = Math.max(y1, pts[i]); }
  for (let j = Math.max(0, Math.floor(y0 / res) - 1); j <= Math.min(H - 1, Math.ceil(y1 / res) + 1); j++) { const y = (j + .5) * res, xs = [];
    for (let i = 0; i < n; i++) { const k = (i + 1) % n, ay = pts[i * 2 + 1], by = pts[k * 2 + 1]; if ((ay <= y) !== (by <= y)) xs.push(pts[i * 2] + (y - ay) / (by - ay) * (pts[k * 2] - pts[i * 2])); }
    xs.sort((a, b) => a - b);
    for (let k = 0; k + 1 < xs.length; k += 2) { const i0 = Math.max(0, Math.ceil(xs[k] / res - .5)), i1 = Math.min(W - 1, Math.floor(xs[k + 1] / res - .5)); for (let i = i0; i <= i1; i++) m[j * W + i] = v; } }
}
function boxBlur(src, W, H, r, passes) {
  let a = Float32Array.from(src); const b = new Float32Array(W * H), k = 1 / (2 * r + 1);
  for (let p = 0; p < passes; p++) {
    for (let j = 0; j < H; j++) { const o = j * W; let s = 0; for (let i = -r; i <= r; i++) s += a[o + clamp(i, 0, W - 1)]; for (let i = 0; i < W; i++) { b[o + i] = s * k; s += a[o + Math.min(W - 1, i + r + 1)] - a[o + Math.max(0, i - r)]; } }
    for (let i = 0; i < W; i++) { let s = 0; for (let j = -r; j <= r; j++) s += b[clamp(j, 0, H - 1) * W + i]; for (let j = 0; j < H; j++) { a[j * W + i] = s * k; s += b[Math.min(H - 1, j + r + 1) * W + i] - b[Math.max(0, j - r) * W + i]; } }
  }
  return a;
}
function distSeg(px, py, ax, ay, bx, by) { const dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy, t = l ? clamp(((px - ax) * dx + (py - ay) * dy) / l, 0, 1) : 0; return Math.hypot(px - ax - dx * t, py - ay - dy * t); }
// поле гор: 1 на гребне, спадает к краям; границу слегка рвёт шум, чтобы хребты не были ровными линиями.
// Вдоль каждого длинного хребта через равные промежутки прорезаны перевалы (место чуть сдвигается от зерна к зерну):
// без них Альпы, Карпаты и прочие хребты были бы сплошной стеной с одной-двумя дырками на краях
function ridgeGrid(W, H, res, n1, n2, rng) {
  const R = new Float32Array(W * H), P = new Float32Array(W * H), T = new Float32Array(W * H), X = new Float32Array(W * H), Y = new Float32Array(W * H);
  for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) { const x = (i + .5) * res, y = (j + .5) * res; X[j * W + i] = x + (n1(x / 260, y / 260) - .5) * 110; Y[j * W + i] = y + (n2(x / 260 + 5, y / 260) - .5) * 110; }
  for (const rd of EU_RIDGES) { const w = rd[0], pts = []; for (let i = 1; i < rd.length; i += 2) pts.push([euX(rd[i]), euY(rd[i + 1])]);
    T.fill(0); let L = 0; const lens = []; for (let s = 0; s < pts.length - 1; s++) { lens.push(Math.hypot(pts[s + 1][0] - pts[s][0], pts[s + 1][1] - pts[s][1])); L += lens[s]; }
    for (let s = 0; s < pts.length - 1; s++) { const [ax, ay] = pts[s], [bx, by] = pts[s + 1], pad = w * 2.6 + 60;
      const i0 = Math.max(0, Math.floor((Math.min(ax, bx) - pad) / res)), i1 = Math.min(W - 1, Math.ceil((Math.max(ax, bx) + pad) / res)), j0 = Math.max(0, Math.floor((Math.min(ay, by) - pad) / res)), j1 = Math.min(H - 1, Math.ceil((Math.max(ay, by) + pad) / res));
      for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) { const k = j * W + i, d = distSeg(X[k], Y[k], ax, ay, bx, by), v = Math.exp(-(d / w) * (d / w)); if (v > T[k]) T[k] = v; } }
    if (L >= 200) { const n = Math.ceil(L / (200 + w * 1.2)), ph = 22 + w * .1; // n перевалов; ph — половина полностью открытого прохода
      for (let q = 0; q < n; q++) { let at = L * (q + .5 + (rng() - .5) * .5) / n, s = 0; while (s < lens.length - 1 && at > lens[s]) { at -= lens[s]; s++; } const t = lens[s] ? at / lens[s] : 0, px = pts[s][0] + (pts[s + 1][0] - pts[s][0]) * t, py = pts[s][1] + (pts[s + 1][1] - pts[s][1]) * t;
        const i0 = Math.max(0, Math.floor((px - ph * 2) / res)), i1 = Math.min(W - 1, Math.ceil((px + ph * 2) / res)), j0 = Math.max(0, Math.floor((py - ph * 2) / res)), j1 = Math.min(H - 1, Math.ceil((py + ph * 2) / res));
        for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) { const k = j * W + i, d = Math.hypot(X[k] - px, Y[k] - py); if (d < ph * 1.4) { const f = clamp((d - ph) / (ph * .4), 0, 1); T[k] *= f; if (1 - f > P[k]) P[k] = 1 - f; } } } }
    for (let k = 0; k < R.length; k++) if (T[k] > R[k]) R[k] = T[k]; }
  R.pass = P; // где прорезаны перевалы: там нет и случайных скал
  return R;
}
function bilin(F, W, H, res, x, y) { const u = x / res - .5, v = y / res - .5, i = Math.floor(u), j = Math.floor(v), fx = u - i, fy = v - j, i0 = clamp(i, 0, W - 1), i1 = clamp(i + 1, 0, W - 1), j0 = clamp(j, 0, H - 1), j1 = clamp(j + 1, 0, H - 1); return (F[j0 * W + i0] * (1 - fx) + F[j0 * W + i1] * fx) * (1 - fy) + (F[j1 * W + i0] * (1 - fx) + F[j1 * W + i1] * fx) * fy; }
// связные области проходимых клеток; main — самая большая
function labelComps(cells) {
  const comp = new Int32Array(GW * GH).fill(-1); let best = -1, bestN = 0, cid = 0;
  for (let s = 0; s < cells.length; s++) { if (comp[s] >= 0 || !TCOST[cells[s]]) continue; let n = 0; const st = [s]; comp[s] = cid; while (st.length) { const c = st.pop(); n++; const ci = c % GW, cj = (c / GW) | 0; for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = ci + a, y = cj + b; if (x < 0 || y < 0 || x >= GW || y >= GH) continue; const k = y * GW + x; if (comp[k] < 0 && TCOST[cells[k]]) { comp[k] = cid; st.push(k); } } } if (n > bestN) { bestN = n; best = cid; } cid++; }
  return { comp, main: best };
}
// Реки Европы: [ширина у устья, долгота, широта, ...] от истока к устью. Река обрывается у моря или впадает в другую реку.
const EU_RIVERS = [
  [17, 8.5, 48.0, 10, 48.4, 12, 48.8, 14, 48.3, 16.5, 48.2, 19, 47.5, 19.1, 46, 20.5, 45.2, 22.5, 44.5, 25, 43.8, 27.5, 44.2, 28.5, 45.3, 29.8, 45.2, 31, 45.2], // Дунай
  [14, 8.6, 46.6, 8.2, 47.6, 7.6, 48.5, 8.4, 49.5, 7.6, 50.3, 6.9, 51, 6, 51.8, 4.5, 51.9, 3.5, 52.4], // Рейн
  [14, 4, 45, 3.5, 46.5, 2.5, 47.4, .5, 47.3, -1.5, 47.3, -2.3, 47.3, -3.2, 47.1], // Луара
  [12, 7, 46.2, 5.9, 45.9, 4.8, 45.3, 4.8, 44, 4.7, 43.5, 4.6, 43.2, 4.5, 42.6], // Рона
  [11, -4, 43, -2.5, 42.4, -.8, 41.7, .5, 41.2, .9, 40.7, 1.6, 40.3], // Эбро
  [13, 7.1, 44.7, 8.5, 45, 10.5, 45, 12, 44.9, 12.8, 44.9, 13.6, 44.9], // По
  [15, 15.5, 50.6, 14.2, 50.5, 13.5, 51, 12.5, 51.8, 11.5, 52.5, 10.5, 53.3, 9.5, 53.7, 8.5, 54, 8, 54.4], // Эльба
  [14, 19, 49.6, 20.3, 50.1, 21.5, 50.6, 21.5, 51.8, 20.6, 52.5, 19.5, 53, 18.8, 53.8, 18.8, 54.8], // Висла
  [17, 32, 56, 31, 55, 30.5, 53.5, 30.8, 52, 31.5, 50.5, 33, 49.5, 34.7, 48.5, 33.5, 47.5, 32.5, 46.7, 31.5, 45.8], // Днепр
  [19, 35, 57.5, 38, 57.2, 41, 57, 44, 56.2, 46, 55.8, 49, 55.5, 49.5, 54, 47.5, 52.5, 46, 51, 45.5, 49, 44.5, 47.5, 47.5, 46.5, 49.5, 46.3], // Волга
];
// Реки: клетки местности 5 непроходимы (TCOST[5] не задан). Мосты — открытые клетки в реке; недостающие мосты добавляются там, где река отрезала земли от главной суши
function genRivers(cells, seed) {
  const R = mulberry(seed + 211), nR = makeNoise(seed + 313), rk = new Uint8Array(GW * GH), bridge = new Uint8Array(GW * GH), rivers = [], bridges = [];
  const kOf = (x, y) => clamp(Math.floor(y / GC), 0, GH - 1) * GW + clamp(Math.floor(x / GC), 0, GW - 1), cx = k => (k % GW) * GC + GC / 2, cy = k => ((k / GW) | 0) * GC + GC / 2;
  EU_RIVERS.forEach((rd, ri) => {
    const w = rd[0], P = []; for (let i = 1; i < rd.length; i += 2) P.push([euX(rd[i]), euY(rd[i + 1])]);
    const D = []; for (let i = 0; i < P.length - 1; i++) { const p0 = P[Math.max(0, i - 1)], p1 = P[i], p2 = P[i + 1], p3 = P[Math.min(P.length - 1, i + 2)], n = Math.max(2, Math.ceil(Math.hypot(p2[0] - p1[0], p2[1] - p1[1]) / 6));
      for (let j = 0; j < n; j++) { const t = j / n, t2 = t * t, t3 = t2 * t; D.push([0, 1].map(a => .5 * (2 * p1[a] + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2 + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3))); } }
    D.push(P[P.length - 1]);
    let s = 0; const M = D.map((p, i) => { if (i) s += Math.hypot(p[0] - D[i - 1][0], p[1] - D[i - 1][1]); const a = D[Math.max(0, i - 2)], b = D[Math.min(D.length - 1, i + 2)], L = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, o = (nR(s / 150, ri * 9.7) - .5) * 48 * Math.min(1, s / 200); return [p[0] - (b[1] - a[1]) / L * o, p[1] + (b[0] - a[0]) / L * o]; });
    const cs = [], curve = [], own = new Set(); let last = -1, started = false, stop = false, join = false;
    const add = k => { if (!cells[k] && !rk[k]) { stop = true; return; } if (rk[k] && !own.has(k)) { if (cs.length > 5) { stop = true; join = true; } return; } if (own.has(k)) return; if (cells[k] === 4) return; cells[k] = 5; rk[k] = ri + 1; own.add(k); cs.push(k); };
    let end = M.length;
    for (let i = 0; i < M.length && !stop; i++) {
      const [x, y] = M[i]; if (x < 0 || y < 0 || x >= WW || y >= WH) continue; const k = kOf(x, y);
      if (!started) { if (!cells[k]) continue; started = true; }
      if (k !== last) { const ci = k % GW, cj = (k / GW) | 0;
        if (last >= 0) { const li = last % GW, lj = (last / GW) | 0; if (ci !== li && cj !== lj) { const ka = lj * GW + ci, kb = cj * GW + li, da = Math.hypot(cx(ka) - x, cy(ka) - y), db = Math.hypot(cx(kb) - x, cy(kb) - y); add(da <= db ? ka : kb); } }
        if (!stop) add(k); last = k; }
      curve.push([Math.round(x * 10) / 10, Math.round(y * 10) / 10]); if (stop) end = i;
    }
    if (stop && !join) for (let i = end + 1; i < Math.min(M.length, end + 5); i++) curve.push([Math.round(M[i][0] * 10) / 10, Math.round(M[i][1] * 10) / 10]); // чуть дальше в море, чтобы устье не обрывалось у берега
    if (join && curve.length) { let bd = 1e9, bp = null; for (const r of rivers) for (const q of r.p) { const d = Math.hypot(q[0] - curve[curve.length - 1][0], q[1] - curve[curve.length - 1][1]); if (d < bd) { bd = d; bp = q; } } if (bp && bd < 60) curve.push(bp); }
    if (cs.length >= 4) rivers.push({ w, p: curve, c: cs });
  });
  const land = k => k >= 0 && k < cells.length && (cells[k] === 1 || cells[k] === 2 || cells[k] === 3);
  const axisOf = k => { const ci = k % GW, W = ci > 0 && land(k - 1), E = ci < GW - 1 && land(k + 1), N = land(k - GW), S = land(k + GW); if (W && E && !N && !S) return 0; if (N && S && !W && !E) return 1; return -1; };
  const open = (k, ax, w) => { cells[k] = 1; rk[k] = 0; bridge[k] = 1; bridges.push({ k, x: cx(k), y: cy(k), ax: ax < 0 ? 0 : ax, w }); };
  for (const r of rivers) { let next = 100 + R() * 120; for (let i = 0; i < r.c.length; i++) { if (i * GC < next) continue; let done = false; for (let j = i; j < Math.min(r.c.length, i + 8) && !done; j++) { const k = r.c[j], ax = axisOf(k); if (ax >= 0) { open(k, ax, r.w * (.55 + .45 * j / r.c.length)); done = true; i = j; } } if (done) next = i * GC + 260 + R() * 200; } }
  // реки не должны отрезать земли: если область отделена только рекой, открываем мост
  for (let pass = 0; pass < 12; pass++) {
    const lab = labelComps(cells), sizes = new Map(); for (let k = 0; k < cells.length; k++) if (lab.comp[k] >= 0) sizes.set(lab.comp[k], (sizes.get(lab.comp[k]) || 0) + 1);
    const best = new Map(); for (let k = 0; k < cells.length; k++) { if (cells[k] !== 5) continue; const ci = k % GW, ns = [ci > 0 ? k - 1 : -1, ci < GW - 1 ? k + 1 : -1, k - GW, k + GW].map(q => q >= 0 && q < cells.length && lab.comp[q] >= 0 ? lab.comp[q] : -1), ids = [...new Set(ns.filter(q => q >= 0))]; if (ids.length < 2) continue; const sc = (axisOf(k) >= 0 ? 2 : 0) + (ids.includes(lab.main) ? 1 : 0); for (const c of ids) { if (c === lab.main || (sizes.get(c) || 0) < 8) continue; const o = best.get(c); if (!o || sc > o.sc) best.set(c, { k, sc }); } }
    if (!best.size) break; for (const { k } of best.values()) if (cells[k] === 5) open(k, axisOf(k), (rivers[rk[k] - 1] || { w: 10 }).w * .8);
  }
  return { rivers, bridges, bridge };
}
function genWorldV2(seed) {
  const nE = makeNoise(seed), nM = makeNoise(seed ^ 0x9e3779b9), nF = makeNoise(seed + 77), nD = makeNoise(seed + 5), nC = makeNoise(seed + 31);
  const RES = 10, LW = WW / RES, LH = WH / RES, mask = new Uint8Array(LW * LH);
  for (const sh of EU_SHAPES) { const pts = []; for (let i = 1; i < sh.length; i += 2) pts.push(euX(sh[i]), euY(sh[i + 1])); polyFill(mask, LW, LH, RES, pts, sh[0]); }
  const Lsh = boxBlur(mask, LW, LH, 2, 2), Lwd = boxBlur(mask, LW, LH, 8, 2), Rid = ridgeGrid(LW, LH, RES, nF, nD, mulberry(seed + 101));
  const carve = new Uint8Array(GW * GH), kOf = (x, y) => clamp(Math.floor(y / GC), 0, GH - 1) * GW + clamp(Math.floor(x / GC), 0, GW - 1);
  // тип местности: 0 море, 1 равнина, 2 лес, 3 холмы, 4 горы
  const bz = (x, y) => { // биом: 0 трава, 1 снег, 2 степь, 3 пустыня
    const lon0 = euLon(x), lat = euLat(y), w1 = nF(x / 200, y / 200) - .5, w2 = nF(x / 330 + 9, y / 330) - .5, lon = lon0 + w2 * 7;
    if (lat > 40 && bilin(Rid, LW, LH, RES, x, y) > .82 + w1 * .3) return 1;
    if (lat > 61.8 + w2 * 3.2) return 1;
    const al = lat + w1 * 2.4;
    if ((al < 37.4 && lon > -10 && lon < 12.5) || al < 36.4 || (lon > -8.5 && lon < -.2 && al < 38.4) || (lon > 49 && al < 43.5) || (lon > 34 && al < 37.6)) return 3;
    const ex = (lon - 42) / 16, ey = (lat - 48.2) / 5.2, hx = (lon - 20) / 2.6, hy = (lat - 47) / 1.3;
    if (ex * ex + ey * ey < 1 + w1 * .7 || hx * hx + hy * hy < 1 + w1) return 2;
    return 0;
  };
  const info = (x, y) => {
    const Ls = bilin(Lsh, LW, LH, RES, x, y), Lw = bilin(Lwd, LW, LH, RES, x, y), e = .33 + (Ls - .5) * .8 + (Lw - .5) * .3 + (nE(x / 240, y / 240) - .5) * .2 + (nC(x / 60, y / 60) - .5) * .16;
    if (e < .33) return { e, t: 0 };
    const m = nM(x / 230, y / 230), r = bilin(Rid, LW, LH, RES, x, y), mt = r * (.55 + .9 * m); let t = 1;
    if (mt > .66 || (m > .78 && bilin(Rid.pass, LW, LH, RES, x, y) < .2)) t = carve[kOf(x, y)] ? 3 : 4;
    else if (mt > .34 || m > .64) t = 3;
    else { const b = bz(x, y); if (b !== 3) { const lat = euLat(y), thr = .62 - .09 * clamp((lat - 47) / 10, -1.2, 1.4) + (b === 2 ? .14 : 0); if (nF(x / 130, y / 130) > thr) t = 2; } }
    return { e, t };
  };
  const biomeAt = (x, y) => ['grass', 'snow', 'steppe', 'arid'][bz(x, y)];
  const cells = new Uint8Array(GW * GH), bio = new Uint8Array(GW * GH);
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) { const x = i * GC + GC / 2, y = j * GC + GC / 2; cells[j * GW + i] = info(x, y).t; bio[j * GW + i] = bz(x, y); }
  // Горы не должны отрезать земли: если проходимая область отделена от главной только хребтом, прорубаем перевал (горы на самом дешёвом пути становятся холмами)
  let lab = labelComps(cells);
  for (let pass = 0; pass < 8; pass++) {
    const sizes = new Map(); for (let k = 0; k < cells.length; k++) if (lab.comp[k] >= 0) sizes.set(lab.comp[k], (sizes.get(lab.comp[k]) || 0) + 1);
    const dist = new Float32Array(cells.length).fill(1e9), prev = new Int32Array(cells.length).fill(-1), h = [];
    for (let k = 0; k < cells.length; k++) if (lab.comp[k] === lab.main) { dist[k] = 0; hpush(h, 0, k); }
    while (h.length) { const [d, c] = hpop(h); if (d > dist[c]) continue; const ci = c % GW, cj = (c / GW) | 0;
      for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = ci + a, y = cj + b; if (x < 0 || y < 0 || x >= GW || y >= GH) continue; const k = y * GW + x; if (!cells[k]) continue; const nd = d + (cells[k] === 4 ? 6 : 1); if (nd < dist[k]) { dist[k] = nd; prev[k] = c; hpush(h, nd, k); } } }
    const bestOf = new Map(); for (let k = 0; k < cells.length; k++) { const c = lab.comp[k]; if (c < 0 || c === lab.main || dist[k] >= 1e9 || (sizes.get(c) || 0) < 8) continue; if (!bestOf.has(c) || dist[k] < dist[bestOf.get(c)]) bestOf.set(c, k); }
    if (!bestOf.size) break;
    for (const k0 of bestOf.values()) for (let k = k0; k >= 0 && dist[k] > 0; k = prev[k]) if (cells[k] === 4) { cells[k] = 3; carve[k] = 1; }
    lab = labelComps(cells);
  }
  const rv = !(G && G.rv === 0), RV = rv ? genRivers(cells, seed) : { rivers: [], bridges: [], bridge: new Uint8Array(GW * GH) };
  if (rv) lab = labelComps(cells);
  WT = { seed, cells, bio, comp: lab.comp, main: lab.main, info, biomeAt, road: new Uint8Array(GW * GH), nF, nD, rv, rivers: RV.rivers, bridges: RV.bridges, bridge: RV.bridge };
  return WT;
}
function genWorldV1(seed) {
  const nE = makeNoise(seed), nM = makeNoise(seed ^ 0x9e3779b9), nF = makeNoise(seed + 77), nD = makeNoise(seed + 5);
  const info = (x, y) => {
    const dx = (x - WW / 2) / (WW / 2), dy = (y - WH / 2) / (WH / 2), f = dx * dx + dy * dy, e = nE(x / 520, y / 520) + .22 - f * .5, m = nM(x / 230, y / 230);
    let t = 1; if (e < .33) t = 0; else if (e > .52 && m > .64) t = 4; else if (m > .56 && e > .4) t = 3; else if (nF(x / 130, y / 130) > .6) t = 2;
    return { e, t };
  };
  const snowLine = x => WH * .27 + (nF(x / 200, 5) - .5) * 160, steppeLine = y => WW * .66 + (nF(7, y / 200) - .5) * 180;
  const biomeAt = (x, y) => y < snowLine(x) ? 'snow' : x > steppeLine(y) ? 'steppe' : 'grass';
  const cells = new Uint8Array(GW * GH), bio = new Uint8Array(GW * GH);
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) { const x = i * GC + GC / 2, y = j * GC + GC / 2; cells[j * GW + i] = info(x, y).t; bio[j * GW + i] = { grass: 0, snow: 1, steppe: 2 }[biomeAt(x, y)]; }
  // крупнейшая проходимая область
  const { comp, main: best } = labelComps(cells);
  WT = { seed, cells, bio, comp, main: best, info, biomeAt, road: new Uint8Array(GW * GH), nF, nD };
  return WT;
}
const cellOf = (x, y) => clamp(Math.floor(y / GC), 0, GH - 1) * GW + clamp(Math.floor(x / GC), 0, GW - 1);
function terrAt(x, y) { return WT.cells[cellOf(x, y)]; }
function biomeName(x, y) { return ['grass', 'snow', 'steppe', 'arid'][WT.bio[cellOf(x, y)]]; }
function cellCost(k) { const t = WT.cells[k]; if (!TCOST[t]) return 0; let c = TCOST[t]; if (WT.bio[k] === 1) c *= 1.25; else if (WT.bio[k] === 3) c *= 1.1; if (WT.road[k]) c *= .55; return c; }

/* ---------- поиск пути ---------- */
const PA = { g: new Float32Array(GW * GH), prev: new Int32Array(GW * GH), closed: new Uint8Array(GW * GH) };
function nearestPass(x, y) { const ci = clamp(Math.floor(x / GC), 0, GW - 1), cj = clamp(Math.floor(y / GC), 0, GH - 1); if (TCOST[WT.cells[cj * GW + ci]]) return [ci, cj]; for (let r = 1; r < 40; r++) for (let j = cj - r; j <= cj + r; j++) for (let i = ci - r; i <= ci + r; i++) { if (i < 0 || j < 0 || i >= GW || j >= GH) continue; if (Math.max(Math.abs(i - ci), Math.abs(j - cj)) !== r) continue; if (TCOST[WT.cells[j * GW + i]] && WT.comp[j * GW + i] === WT.main) return [i, j]; } return [ci, cj]; }
function hpush(h, f, v) { h.push([f, v]); let i = h.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (h[p][0] <= h[i][0]) break; [h[p], h[i]] = [h[i], h[p]]; i = p; } }
function hpop(h) { const top = h[0], last = h.pop(); if (h.length) { h[0] = last; let i = 0; for (; ;) { let l = i * 2 + 1, r = l + 1, m = i; if (l < h.length && h[l][0] < h[m][0]) m = l; if (r < h.length && h[r][0] < h[m][0]) m = r; if (m === i) break; [h[m], h[i]] = [h[i], h[m]]; i = m; } } return top; }
function losClear(x0, y0, x1, y1) { const d = Math.hypot(x1 - x0, y1 - y0), n = Math.ceil(d / (GC * (WT.rv ? .25 : .5))); for (let i = 1; i < n; i++) { const t = i / n; if (!TCOST[terrAt(lerp(x0, x1, t), lerp(y0, y1, t))]) return false; } return true; }
function findPath(sx, sy, tx, ty, raw) { // raw: путь по центрам клеток без упрощения (для дорог)
  const [a, b] = nearestPass(sx, sy), [c, d] = nearestPass(tx, ty), s = b * GW + a, e = d * GW + c; if (s === e) return [{ x: tx, y: ty }];
  PA.g.fill(1e9); PA.closed.fill(0); const h = []; PA.g[s] = 0; PA.prev[s] = -1; hpush(h, 0, s); let found = false;
  while (h.length) { const [, cur] = hpop(h); if (PA.closed[cur]) continue; PA.closed[cur] = 1; if (cur === e) { found = true; break; } const ci = cur % GW, cj = (cur / GW) | 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { if (!di && !dj) continue; const ni = ci + di, nj = cj + dj; if (ni < 0 || nj < 0 || ni >= GW || nj >= GH) continue; const k = nj * GW + ni; if (PA.closed[k]) continue; const cc = cellCost(k); if (!cc) continue; if (di && dj && (!cellCost(cj * GW + ni) || !cellCost(nj * GW + ci))) continue; const g = PA.g[cur] + cc * (di && dj ? 1.414 : 1); if (g < PA.g[k]) { PA.g[k] = g; PA.prev[k] = cur; hpush(h, g + Math.hypot(ni - c, nj - d) * .55, k); } } }
  if (!found) return null;
  const pts = []; for (let k = e; k >= 0; k = PA.prev[k]) pts.push({ x: (k % GW) * GC + GC / 2, y: ((k / GW) | 0) * GC + GC / 2 }); pts.reverse(); pts[0] = { x: sx, y: sy }; pts[pts.length - 1] = { x: tx, y: ty };
  if (!TCOST[terrAt(tx, ty)]) pts[pts.length - 1] = pts[pts.length - 2] || pts[0];
  if (raw) return pts.filter((q, i) => i && (q.x !== pts[i - 1].x || q.y !== pts[i - 1].y));
  const out = [pts[0]]; let i = 0; while (i < pts.length - 1) { let j = pts.length - 1; while (j > i + 1 && !losClear(pts[i].x, pts[i].y, pts[j].x, pts[j].y)) j--; out.push(pts[j]); i = j; } out.shift(); return out;
}

/* ---------- создание мира ---------- */
function mkSettle(kind, fac, name, x, y) { return { id: G.nid++, kind, fac, name, x, y, recruits: [], rt: 0, pros: rint(2, 5), camp: null, cleared: false, respawn: 0, hv: 0 }; }
function genSettlements() {
  if (isEU()) return genSettlementsV2();
  const R = mulberry(G.seed + 11), W = WT; const ok = (x, y, md) => { const k = cellOf(x, y); if (W.comp[k] !== W.main || W.cells[k] !== 1) return false; for (const s of G.settles) if (Math.hypot(s.x - x, s.y - y) < md) return false; return true; };
  const reg = { nord: [.08, .08, .46, .38], emp: [.12, .5, .6, .9], khan: [.64, .2, .92, .8] };
  const place = (fac, kind, name, md) => { const r = reg[fac]; let x, y, tries = 0; do { x = rnd2(R, r[0] * WW, r[2] * WW); y = rnd2(R, r[1] * WH, r[3] * WH); tries++; if (tries > 400) { r[0] = Math.max(.03, r[0] - .03); r[1] = Math.max(.03, r[1] - .03); r[2] = Math.min(.97, r[2] + .03); r[3] = Math.min(.97, r[3] + .03); tries = 0; } } while (!ok(x, y, md)); const s = mkSettle(kind, fac, name, x, y); G.settles.push(s); return s; };
  for (const f of ['nord', 'emp', 'khan']) { const n = SNAMES[f]; place(f, 'town', n.town[0], 260); place(f, 'town', n.town[1], 260); place(f, 'castle', n.castle[0], 220); place(f, 'castle', n.castle[1], 220); for (let i = 0; i < 3; i++) place(f, 'village', n.village[i], 130); }
  for (let i = 0; i < 4; i++) { const f = ['nord', 'emp', 'khan', 'emp'][i], r = reg[f]; let x, y, t = 0; do { x = rnd2(R, .05 * WW, .95 * WW); y = rnd2(R, .05 * WH, .95 * WH); t++; } while (!ok(x, y, 170) && t < 2000); const s = mkSettle('camp', 'bandit', CAMPN[i], x, y); G.settles.push(s); }
}
const rnd2 = (R, a, b) => a + R() * (b - a);
// Европа: фракции живут каждая в своих землях (эллипсы в EU_REG). Столицы ставятся первыми, остальное — вразброс: из нескольких подходящих мест берётся самое далёкое от соседей
function genSettlementsV2() {
  const R = mulberry(G.seed + 11), W = WT, F = worldF();
  const ok = (x, y, md) => { if (x < 90 || y < 90 || x > WW - 90 || y > WH - 90) return false; const k = cellOf(x, y); if (W.comp[k] !== W.main || W.cells[k] !== 1) return false; if (W.rv) { const ci = k % GW, cj = (k / GW) | 0; for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { const a = ci + di, b = cj + dj; if (a >= 0 && b >= 0 && a < GW && b < GH && W.cells[b * GW + a] === 5) return false; } } for (const s of G.settles) if (Math.hypot(s.x - x, s.y - y) < md) return false; return true; };
  const spot = (discs, sc) => { let tot = 0; for (const d of discs) tot += d[2] * d[3]; let q = R() * tot, d = discs[discs.length - 1]; for (const c of discs) { if (q < c[2] * c[3]) { d = c; break; } q -= c[2] * c[3]; } const a = R() * TAU, r = Math.sqrt(R()); return [euX(d[0] + Math.cos(a) * r * d[2] * sc), euY(d[1] + Math.sin(a) * r * d[3] * sc)]; };
  const place = (fac, kind, name, md, discs, k) => { let best = null, bd = -1, tries = 0, found = 0, sc = 1;
    while (found < k && tries < 1500) { tries++; if (tries % 250 === 0) sc *= 1.2; const [x, y] = spot(discs, sc); if (!ok(x, y, md)) continue; found++; let d = 1e9; for (const s of G.settles) d = Math.min(d, Math.hypot(s.x - x, s.y - y)); if (d > bd) { bd = d; best = [x, y]; } }
    if (!best) { sc = 1; do { const [x, y] = spot(discs, 3 + tries / 500); if (ok(x, y, md * .6)) best = [x, y]; tries++; } while (!best && tries < 6000); }
    const s = mkSettle(kind, fac, name, best[0], best[1]); G.settles.push(s); return s; };
  for (const f of F) place(f, 'town', SNAMES2[f].town[0], 300, [EU_REG[f].cap], 1);
  for (let i = 1; i < 4; i++) for (const f of F) place(f, 'town', SNAMES2[f].town[i], 300, EU_REG[f].discs, 8);
  for (let i = 0; i < 3; i++) for (const f of F) place(f, 'castle', SNAMES2[f].castle[i], 240, EU_REG[f].discs, 8);
  for (let i = 0; i < 8; i++) for (const f of F) place(f, 'village', SNAMES2[f].village[i], 150, EU_REG[f].discs, 6);
  // разбойничьи лагеря: у каждой фракции и в диких краях
  for (let i = 0; i < CAMPN2.length; i++) { const f = i < 10 ? F[i % F.length] : 'wild'; place('bandit', 'camp', CAMPN2[i], 200, EU_REG[f].discs, 4); }
}
// Путь по клеткам идёт отрезками в 8 направлениях: точки на прямых участках лишние (кроме мостов — они нужны для рисования)
function thinPath(seg) {
  const out = [seg[0]]; for (let i = 1; i < seg.length - 1; i++) { const ax = seg[i].x - seg[i - 1].x, ay = seg[i].y - seg[i - 1].y, bx = seg[i + 1].x - seg[i].x, by = seg[i + 1].y - seg[i].y; if (Math.abs(ax * by - ay * bx) < 1e-6 && ax * bx + ay * by > 0 && !WT.bridge[cellOf(seg[i].x, seg[i].y)]) continue; out.push(seg[i]); } out.push(seg[seg.length - 1]); return out;
}
function genRoads() {
  const towns = G.settles.filter(s => s.kind !== 'camp'); WT.road.fill(0);
  const addRoad = seg => { for (let i = 0; i < seg.length - 1; i++) { const n = Math.ceil(Math.hypot(seg[i + 1].x - seg[i].x, seg[i + 1].y - seg[i].y) / 8); for (let k = 0; k <= n; k++) WT.road[cellOf(lerp(seg[i].x, seg[i + 1].x, k / n), lerp(seg[i].y, seg[i + 1].y, k / n))] = 1; } G.roads.push(seg); };
  const link = (a, b) => { const raw = !!WT.rv, p = findPath(a.x, a.y, b.x, b.y, raw); if (!p) return false; let seg = [{ x: a.x, y: a.y }, ...p]; if (raw) seg = thinPath(seg); addRoad(seg); return true; };
  G.roads = []; const done = new Set();
  if (isEU()) { // каркас дорог: все поселения связаны в одну сеть (минимальное остовное дерево), а не только с двумя ближайшими соседями
    const ed = []; for (let i = 0; i < towns.length; i++) for (let j = i + 1; j < towns.length; j++) ed.push([Math.hypot(towns[i].x - towns[j].x, towns[i].y - towns[j].y), i, j]); ed.sort((p, q) => p[0] - q[0]);
    const up = towns.map((_, i) => i), fd = i => { while (up[i] !== i) i = up[i] = up[up[i]]; return i; };
    for (const [d, i, j] of ed) { if (d > 1500) break; if (fd(i) === fd(j)) continue; if (link(towns[i], towns[j])) { up[fd(i)] = fd(j); done.add(Math.min(towns[i].id, towns[j].id) + '-' + Math.max(towns[i].id, towns[j].id)); } } }
  for (const a of towns) { const ds = towns.filter(b => b !== a).sort((p, q) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y)); let n = 0; for (const b of ds) { const key = Math.min(a.id, b.id) + '-' + Math.max(a.id, b.id); if (done.has(key)) { n++; if (n >= 2) break; continue; } done.add(key); link(a, b); if (++n >= 2) break; } }
  for (const c of G.settles.filter(s => s.kind === 'camp')) { const b = towns.sort((p, q) => Math.hypot(p.x - c.x, p.y - c.y) - Math.hypot(q.x - c.x, q.y - c.y))[0]; if (Math.hypot(b.x - c.x, b.y - c.y) < 380) link(c, b); }
  // у каждого моста должна быть дорога: недостающие тянем от моста к ближайшему поселению на каждом берегу
  if (WT.rv) for (const b of WT.bridges) { if (WT.road[b.k]) continue;
    for (const sg of [-1, 1]) { const at = n => b.ax === 0 ? { x: b.x + sg * GC * n, y: b.y } : { x: b.x, y: b.y + sg * GC * n }, sp = at(1); if (!TCOST[terrAt(sp.x, sp.y)]) continue;
      let t = null, bd = 900; for (const q of towns) { const d = Math.hypot(q.x - sp.x, q.y - sp.y); if (d < bd) { bd = d; t = q; } }
      let tail = t ? findPath(sp.x, sp.y, t.x, t.y, true) : null; if (!tail) { tail = []; for (let n = 2; n < 5; n++) { const q = at(n); if (TCOST[terrAt(q.x, q.y)]) tail.push(q); else break; } }
      addRoad(thinPath([{ x: b.x, y: b.y }, sp, ...tail])); } }
}
function genRecruits(s) {
  if (s.fac === 'bandit' || s.fac === 'undead' || s.burnt > 0) { if (s.fac !== 'bandit') s.recruits = []; return; } const f = sCult(s), out = {}, n = (s.kind === 'town' ? rint(5, 9) : s.kind === 'castle' ? rint(3, 6) : rint(3, 7)) * MK();
  for (let i = 0; i < n; i++) { const ids = Object.keys(TROOPS).filter(k => TROOPS[k].fac === f && TROOPS[k].tier <= (s.kind === 'village' ? 1 : s.kind === 'town' ? 2 : 3) && (s.kind !== 'castle' || TROOPS[k].tier >= 2) && (s.kind === 'village' || TROOPS[k].tier >= 1)); let id = pick(ids.length ? ids : Object.keys(TROOPS).filter(k => TROOPS[k].fac === f)); if (s.kind === 'village' && TROOPS[id].tier > 1) id = Object.keys(TROOPS).find(k => TROOPS[k].fac === f && TROOPS[k].tier === 1); out[id] = (out[id] || 0) + 1; }
  s.recruits = Object.keys(out).map(k => ({ type: k, n: out[k] }));
}
function lordName(fac) { const f = FACTIONS[fac]; return f.title[0].toUpperCase() + f.title.slice(1) + ' ' + unitName(fac); }
function partyStr(p) { return strength(p.troops); }
/* Армии лордов: большие, как в Mount & Blade. Начальный размер, размер нового лорда (после гибели прежнего) и до скольких лорд пополняется в своих землях */
const lordsPerF = () => isEU() ? 5 : 3; // лордов на фракцию: на большой карте больше
const LORD_MIN = 130, LORD_MAX = 190, LORD_NEW_MIN = 95, LORD_NEW_MAX = 145, LORD_FULL = 165;
/* Вассалы: средние отряды фракций между шайками (10–20) и лордами (130–190). Служат лорду своей фракции: то идут за ним, то объезжают свои земли.
   В поселениях не прячутся (стоят у стен), в осадах не участвуют. На старых сохранениях появляются постепенно, как новые лорды. */
const vassalsPerF = () => isEU() ? 4 : 2;
const VAS_MIN = 50, VAS_MAX = 80, VAS_NEW_MIN = 35, VAS_NEW_MAX = 55, VAS_FULL = 70;
const VAS_TITLE = { nord: 'Хёвдинг', emp: 'Трибун', khan: 'Багатур', kin: 'Шевалье', emi: 'Сипахи' };
function vassalName(fac) { return (VAS_TITLE[fac] || 'Вассал') + ' ' + unitName(fac); }
const isNoble = p => p.kind === 'lord' || p.kind === 'vassal';
function spawnVassal(f, h, n) { const lords = G.parties.filter(q => q.kind === 'lord' && q.fac === f), p = mkParty('vassal', f, vassalName(f), h.x + rnd(-20, 20), h.y + 24, genTroops(f, n, .55), { home: h.id, lid: lords.length ? pick(lords).id : null }); p.state = 'idle'; p.wait = rint(1, 12); return p; }
function mkParty(kind, fac, name, x, y, troops, extra) { const p = Object.assign({ id: G.nid++, kind, fac, name, x, y, troops, path: [], pi: 0, tid: null, sid: null, home: null, state: 'idle', wait: 0, hide: false, gold: 0, hold: 0, cd: 0 }, extra || {}); G.parties.push(p); return p; }
function partyById(id) { return G.parties.find(p => p.id === id); }
function settleById(id) { return G.settles.find(s => s.id === id); }
function sizeCap(h) { heroFix(h); return (20 + h.cha * 5 + (h.lvl - 1) * 3 + perkFx(h).size) * MK(); }
function leaderType(p) { let b = null, bs = -1; for (const s of p.troops) { const t = TROOPS[s.type], v = t.tier * 10 + s.n * .01; if (v > bs) { bs = v; b = s.type; } } return b; }
function addT(list, type, n) { const f = list.find(s => s.type === type); if (f) f.n += n; else list.push({ type, n }); }
function remT(list, type, n) { const f = list.find(s => s.type === type); if (!f) return; f.n -= n; if (f.n <= 0) list.splice(list.indexOf(f), 1); }
function sortT(list) { list.sort((a, b) => TROOPS[b.type].tier - TROOPS[a.type].tier || (a.type < b.type ? -1 : 1)); }

const CULT = {
  nord: { start: [['n1', 6], ['n2a', 2], ['n2s', 2]], horse: 0 }, emp: { start: [['e1', 6], ['e2a', 3], ['e2s', 1]], horse: 0 }, khan: { start: [['k1', 5], ['k2a', 3], ['k2c', 2]], horse: 1 },
  kin: { start: [['f1', 6], ['f2a', 3], ['f2s', 1]], horse: 0 }, dom: { start: [['d1', 6], ['d2x', 3], ['d2s', 1]], horse: 0 }, pact: { start: [['p1', 6], ['p2a', 3], ['p2s', 1]], horse: 0 }, emi: { start: [['m1', 5], ['m2a', 3], ['m2c', 2]], horse: 1 }
};
function newWorld(seed, mapv) {
  seed = seed || rint(1, 1e9); G = { seed, mapv: mapv || DEFAULT_MAPV, rv: (mapv || DEFAULT_MAPV) >= 2 ? 1 : 0, nid: 1, day: 1, hour: 8, acc: 0, speed: 1, paused: false, parties: [], settles: [], roads: [], players: [], player: null, log: [], stats: { wins: 0, kills: 0 }, ver: 2 };
  genWorld(seed); genSettlements(); genRoads(); for (const s of G.settles) { genRecruits(s); if (s.kind === 'camp') respawnCamp(s); }
  for (const f of worldF()) { const hs = G.settles.filter(s => s.fac === f); const nl = lordsPerF(); for (let i = 0; i < nl; i++) { const h = isEU() ? (i === 0 ? hs[0] : pick(hs.filter(s => s.kind !== 'village'))) : hs[i % 2 === 0 ? 0 : rint(0, hs.length - 1)]; const p = mkParty('lord', f, lordName(f), h.x + 12, h.y + 20, genTroops(f, rint(LORD_MIN, LORD_MAX), .6), { home: h.id }); p.state = 'idle'; p.wait = rint(1, 20); } }
  for (const f of worldF()) { const hs = G.settles.filter(s => s.fac === f && s.kind !== 'camp'); for (let i = 0; i < vassalsPerF() && hs.length; i++) spawnVassal(f, pick(hs), rint(VAS_MIN, VAS_MAX)); }
  for (let i = 0; i < (isEU() ? 8 : 2); i++) { const t = pick(G.settles.filter(s => s.kind === 'town')); spawnCaravan(t); }
  genQuests(); return G;
}
function mkPlayer(o) {
  const home = G.settles.filter(s => s.fac === o.culture && s.kind === 'town')[0], troops = CULT[o.culture].start.map(a => ({ type: a[0], n: a[1] })), nm = (o.name || 'Безымянный').slice(0, 18);
  let px = home.x + 10 + rnd(-24, 24), py = home.y + 34; if (!TCOST[terrAt(px, py)]) { px = home.x; py = home.y; }
  return { id: G.nid++, x: px, y: py, troops, gold: 650, food: SERVER ? 60 : 0, inv: SERVER ? {} : { grain: 10 }, path: [], pi: 0, tid: null, sid: null, in: null, name: nm, culture: o.culture, banner: o.banner || 0, fx: 1, busy: null, away: false, log: [], logDirty: true, quests: [], rel: { nord: 0, emp: 0, khan: 0, kin: 0, emi: 0, dom: 0, pact: 0, bandit: -100 }, stats: { wins: 0, kills: 0 },
    hero: { name: nm, lvl: 1, xp: 0, pts: PTS_START, pp: PP_START, perks: [], str: 1, vit: 1, agi: 1, int: 1, cha: 1, armor: 0, weapon: 0, shield: 0, horse: CULT[o.culture].horse, hp: 1, seed: rint(1, 99999) } };
}
function addPlayer(o) { const P = mkPlayer(o); relWatch(P); G.players.push(P); const h = G.settles.find(s => s.fac === o.culture && s.kind === 'town'); logW('Ты прибыл в ' + h.name.replace(/а$/, 'у').replace(/я$/, 'ю') + '. Собери отряд и заработай имя.', 0, P); return P; }
function newGame(o) { newWorld(o.seed); const P = addPlayer(o); G.player = P; FACTIONS.player.c1 = BANNERS[P.banner].c1; FACTIONS.player.c2 = BANNERS[P.banner].c2; return G; }
function respawnCamp(c) { c.camp = mkParty('camp', 'bandit', 'Лагерь: ' + c.name, c.x, c.y, genTroops('bandit', rint(12, 20), .4), { home: c.id, hide: false }); c.cleared = false; c.camp.camp = c.id; }
function spawnCaravan(t) { if (!t || !REAL_F.includes(t.fac)) return null; const dsts = G.settles.filter(s => s.kind === 'town' && s !== t && REAL_F.includes(s.fac)); if (!dsts.length) return null; const nr = isEU() ? dsts.filter(s => Math.hypot(s.x - t.x, s.y - t.y) < 1300) : dsts, dst = pick(nr.length ? nr : dsts); const p = mkParty('caravan', t.fac, 'Караван', t.x + 10, t.y + 20, genTroops(t.fac, rint(3, 5), .3), { home: t.id, sid: dst.id, state: 'travel' }); p.path = findPath(p.x, p.y, dst.x, dst.y) || []; p.pi = 0; return p; }
function logW(txt, kind, P) { const L = P ? P.log : G.log; L.push({ txt, kind: kind || 0, d: G.day }); if (L.length > 40) L.shift(); if (P) { P.logDirty = true; P.logN = (P.logN || 0) + 1; } else G.logDirty = true; }
function relName(v) { return v < -20 ? 'Враждебные' : v < -5 ? 'Недружелюбные' : v < 20 ? 'Нейтральные' : v < 50 ? 'Дружелюбные' : 'Союзные'; }

/* ---------- задания ---------- */
function genQuests() {
  for (const s of G.settles) { if (s.kind !== 'town') continue; s.board = s.board || []; if (!REAL_F.includes(s.fac)) { s.board = []; continue; } s.board = s.board.filter(q => G.day - q.day < 12); while (s.board.length < 3) {
    let camps = G.settles.filter(c => c.kind === 'camp'); if (isEU()) camps = camps.sort((a, b) => Math.hypot(a.x - s.x, a.y - s.y) - Math.hypot(b.x - s.x, b.y - s.y)).slice(0, 3);
    const near = (list, k) => { list = list.filter(x => x !== s); if (isEU()) list = list.sort((a, b) => Math.hypot(a.x - s.x, a.y - s.y) - Math.hypot(b.x - s.x, b.y - s.y)).slice(0, k); return list; };
    const base = { id: G.nid++, from: s.id, fac: s.fac, day: G.day }, kinds = ['deliver', 'deliver', 'supply', 'supply', 'purge', 'muster'].concat(camps.length ? ['camp', 'camp', 'scout'] : []), kind = pick(kinds);
    if (kind === 'camp') { const c = pick(camps); s.board.push(Object.assign(base, { type: 'camp', sid: c.id, reward: rint(300, 520), dl: G.day + 20 })); }
    else if (kind === 'scout') { const c = pick(camps); s.board.push(Object.assign(base, { type: 'scout', sid: c.id, seen: false, reward: rint(160, 260), dl: G.day + 14 })); }
    else if (kind === 'purge') { const n = rint(2, 3); s.board.push(Object.assign(base, { type: 'purge', sid: s.id, n, got: 0, reward: 150 + n * 90, dl: G.day + 16 })); }
    else if (kind === 'supply') { const ds = near(G.settles.filter(x => x.kind === 'town' || x.kind === 'castle'), 6), d = ds.length ? pick(ds) : null; if (!d) continue; const ids = Object.keys(GOODS).filter(k => !GOODS[k].lux), item = pick(ids), n = rint(6, 14), dist = Math.hypot(d.x - s.x, d.y - s.y); s.board.push(Object.assign(base, { type: 'supply', sid: d.id, item, n, reward: Math.round(n * GOODS[item].p * 1.3 + dist * .15 + 40), dl: G.day + Math.ceil(dist / 150) + 8 })); }
    else if (kind === 'muster') { const ds = near(G.settles.filter(x => (x.kind === 'town' || x.kind === 'castle') && x.fac === s.fac), 4), d = ds.length ? pick(ds) : null; if (!d) continue; const n = rint(6, 12), dist = Math.hypot(d.x - s.x, d.y - s.y); s.board.push(Object.assign(base, { type: 'muster', sid: d.id, n, reward: Math.round(n * 48 + dist * .1), dl: G.day + Math.ceil(dist / 150) + 8 })); }
    else { const ds = near(G.settles.filter(x => x.kind !== 'camp'), 8), d = pick(ds), dist = Math.hypot(d.x - s.x, d.y - s.y); s.board.push(Object.assign(base, { type: 'deliver', sid: d.id, reward: Math.round(90 + dist * .22), dl: G.day + Math.ceil(dist / 150) + 4 })); } } }
}
function questText(q) { const s = settleById(q.sid), f = settleById(q.from); switch (q.type) {
  case 'camp': return 'Разгромить разбойников: «' + s.name + '»';
  case 'scout': return 'Разведать лагерь «' + s.name + '» и вернуться в ' + f.name;
  case 'purge': return 'Разбить разбойничьи отряды в пути: ' + q.n + ' (' + (q.got || 0) + '/' + q.n + ')';
  case 'supply': return 'Привезти в ' + s.name + ': ' + GOODS[q.item].n.toLowerCase() + ' ×' + q.n;
  case 'muster': return 'Прислать в гарнизон ' + s.name + ' бойцов 2 уровня и выше: ' + q.n;
  default: return 'Доставить груз в ' + s.name; } }
function questDetail(q, from) { const s = settleById(q.sid), lg = x => Math.round(Math.hypot(x.x - from.x, x.y - from.y) / 10) / 10 + ' лиг';
  switch (q.type) { case 'camp': case 'scout': return 'Расстояние: ' + lg(s); case 'purge': return 'Любые разбойничьи отряды на дорогах'; case 'supply': return 'Товар покупаешь сам, расстояние: ' + lg(s); case 'muster': return 'Бойцы переходят в гарнизон, расстояние: ' + lg(s); default: return 'Груз уже погружен'; } }
/* прогресс заданий: вход в поселение, победа над отрядом, ход часов (разведка) */
function questsOnEnter(P, s) {
  for (const q of P.quests.slice()) {
    if (q.type === 'deliver' && q.sid === s.id) questDone(P, q, true);
    else if (q.type === 'scout' && q.seen && q.from === s.id) questDone(P, q, true);
    else if (q.type === 'supply' && q.sid === s.id) { if (invN(P, q.item) >= q.n) { invAdd(P, q.item, -q.n); questDone(P, q, true); } else logW('Для задания нужно ещё: ' + GOODS[q.item].n.toLowerCase() + ' ×' + (q.n - invN(P, q.item)), 0, P); }
    else if (q.type === 'muster' && q.sid === s.id) { const pool = P.troops.filter(t => TROOPS[t.type].tier >= 2).sort((a, b) => TROOPS[a.type].tier - TROOPS[b.type].tier); let have = 0; for (const t of pool) have += t.n; if (have >= q.n && troopCount(P.troops) - q.n >= 1) { let need = q.n; for (const t of pool) { const k = Math.min(t.n, need); if (k > 0) { remT(P.troops, t.type, k); addT(garrisonOf(s), t.type, k); need -= k; } } sortT(garrisonOf(s)); questDone(P, q, true); } else logW('Для задания нужно бойцов 2 уровня и выше: ' + q.n + ' (у тебя ' + have + ')', 0, P); }
  }
}
function questsScoutTick() { for (const P of G.players) { if (P.away || P.busy === 'battle') continue; for (const q of P.quests) if (q.type === 'scout' && !q.seen) { const c = settleById(q.sid); if (c && Math.hypot(c.x - P.x, c.y - P.y) < 120) { q.seen = true; logW('Лагерь «' + c.name + '» разведан. Возвращайся в ' + settleById(q.from).name + '.', 1, P); } } } }
function acceptQuest(P, q) { const t = settleById(q.from); if (P.quests.length >= 4) return 'Не больше четырёх заданий одновременно.'; if (t.board.indexOf(q) < 0) return 'Задание уже взято.'; t.board.splice(t.board.indexOf(q), 1); P.quests.push(q); return null; }
function questDone(P, q, why) { P.quests.splice(P.quests.indexOf(q), 1); if (why) { const rw = Math.round(q.reward * (1 + perkFx(P.hero).quest)); P.gold += rw; P.rel[q.fac] = Math.min(100, P.rel[q.fac] + 6); sfx('coin'); logW('Задание выполнено: ' + questText(q) + '. Награда: ' + rw + ' золота.', 3, P); } }

/* ---------- ход времени ---------- */
function speedOf(p) {
  let m = 1, base = 17, any = false, mo = true; for (const s of p.troops) { any = true; if (!TROOPS[s.type].mounted) mo = false; } if (any && mo) base = 22;
  if (p.hero) { base = (p.hero.horse && mo ? 22 : base) + 1; if (provOf(p) <= 0) base *= .85; if (p.troops.length > 14) base *= .96; base *= 1 + perkFx(p.hero).map; }
  const k = cellOf(p.x, p.y), t = WT.cells[k]; m = t === 2 ? .72 : t === 3 ? .78 : 1; if (WT.bio[k] === 1) m *= .85; if (WT.road[k]) m *= 1.3; if (p.kind === 'bandit') m *= 1.04; return base * m;
}
function moveAlong(p, dh) { let rem = speedOf(p) * dh; while (rem > 0 && p.pi < p.path.length) { const t = p.path[p.pi], dx = t.x - p.x, dy = t.y - p.y, d = Math.hypot(dx, dy); if (d <= rem) { p.x = t.x; p.y = t.y; p.pi++; rem -= d; } else { p.x += dx / d * rem; p.y += dy / d * rem; p.fx = dx / d; rem = 0; } } return p.pi >= p.path.length; }
function pathTo(p, x, y) { const pa = findPath(p.x, p.y, x, y); p.path = pa || []; p.pi = 0; return !!pa; }
/* Отряд уже занят встречей или боем другого игрока (мультиплеер): вступать с ним в бой второй раз нельзя, иначе враги двоятся.
   Блокировка от игрока, который вышел или свободен, считается устаревшей и отряд не держит. В одиночной игре p.lock не ставится. */
function lockedByOther(p, P) { if (!p.lock || p.lock === P.id) return false; const Q = G.players.find(q => q.id === p.lock); return !!(Q && !Q.away && (Q.busy === 'enc' || Q.busy === 'battle')); }
function stepWorld(dh) {
  const evs = [], claimed = new Set(); // claimed: отряды, с которыми встреча уже создана в этом такте
  const meet = (P, p, forced) => { if (claimed.has(p) || lockedByOther(p, P)) return false; claimed.add(p); evs.push({ type: 'meet', P, p, forced }); return true; };
  for (const P of G.players) {
    if (P.away || P.in || P.busy) continue;
    let tg = P.tid != null ? partyById(P.tid) : null; if (P.tid != null && (!tg || tg.hide)) { P.tid = null; P.path = []; tg = null; }
    if (tg) { P.rp = (P.rp || 0) - dh; if (P.rp <= 0) { P.rp = .6; if (losClear(P.x, P.y, tg.x, tg.y)) P.path = [{ x: tg.x, y: tg.y }]; else P.path = findPath(P.x, P.y, tg.x, tg.y) || []; P.pi = 0; } }
    if (P.path.length && P.pi < P.path.length) { const arrived = moveAlong(P, dh); if (arrived && !tg) { P.path = []; if (P.sid != null) { const s = settleById(P.sid); P.sid = null; if (s && Math.hypot(s.x - P.x, s.y - P.y) < 40) { evs.push({ type: 'enter', P, s }); continue; } } } }
    if (tg && Math.hypot(tg.x - P.x, tg.y - P.y) < 24) { P.tid = null; P.path = []; if (!meet(P, tg, false)) logW('Этот отряд уже в бою с другом.', 0, P); continue; }
    for (const p of G.parties) { if (p.hide || p.kind === 'camp' || p.lock) continue; if (Math.hypot(p.x - P.x, p.y - P.y) < 22 && isHostileToPlayer(p, P) && p.cd <= 0 && meet(P, p, true)) break; }
  }
  // ИИ
  for (const p of G.parties.slice()) { if (!G.parties.includes(p)) continue; aiParty(p, dh); }
  for (let i = 0; i < G.parties.length; i++) { const a = G.parties[i]; if (a.hide || a.kind === 'camp' || a.lock || a.fight || !G.parties.includes(a)) continue; for (let j = i + 1; j < G.parties.length; j++) { const b = G.parties[j]; if (b.hide || b.kind === 'camp' || b.lock || b.fight || !G.parties.includes(b)) continue; if (Math.hypot(a.x - b.x, a.y - b.y) < 15 && hostile(a, b)) { if (typeof warContact === 'function') warContact(a, b); else autoFight(a, b); break; } } }
  return evs;
}
function isHostileToPlayer(p, P) { if (p.kind === 'bandit' || p.kind === 'camp' || p.fac === 'undead') return true; if (p.kind === 'caravan') return false; return P.rel[p.fac] < -20; }
function hostile(a, b) { if ((a.fac === 'undead') !== (b.fac === 'undead')) return true; if (a.fac === 'undead') return false; if (a.kind === 'caravan' && b.kind === 'caravan') return false; if (a.kind === 'bandit' && b.fac !== 'bandit') return true; if (b.kind === 'bandit' && a.fac !== 'bandit') return true; return a.fac !== b.fac && atWar(a.fac, b.fac) && a.kind !== 'caravan' && b.kind !== 'caravan'; }
function aiParty(p, dh) {
  if (p.kind === 'camp') return; p.cd -= dh; if (p.lock || p.fight) return;
  if (p.hide) { p.wait -= dh; if (p.wait <= 0) { p.hide = false; const h = settleById(p.home); if (h) { const lord = p.kind === 'lord', need = Math.max(0, (lord ? LORD_FULL : 34) * MK() - troopCount(p.troops)); if (need > 0 && h.fac === p.fac) { const add = genTroops(p.fac, Math.min(Math.ceil(need / MK()), lord ? rint(10, 25) : rint(4, 10)), .6); for (const a of add) addT(p.troops, a.type, a.n); } } if (p.kind === 'lord') p.state = 'idle'; } return; }
  p.ai = (p.ai || 0) - dh;
  if (p.ai <= 0) { p.ai = rnd(.8, 1.6);
    const me = partyStr(p) + (typeof warAllyStr === 'function' ? warAllyStr(p) : 0);
    // охота / бегство
    let tgt = null, tb = 1e9, threat = null;
    for (const o of G.parties) { if (o === p || o.hide || o.kind === 'camp') continue; if (!hostile(p, o)) continue; const d = Math.hypot(o.x - p.x, o.y - p.y); if (d > 260) continue; const so = partyStr(o); if (so < me * (p.kind === 'bandit' ? .9 : .75)) { if (d < tb) { tb = d; tgt = o; } } else if (so > me * 1.2 && d < 190) threat = o; }
    for (const Q of G.players) { if (Q.in || Q.away || Q.busy || !isHostileToPlayer(p, Q)) continue; const d = Math.hypot(Q.x - p.x, Q.y - p.y); if (d < 230) { const sp = strength(Q.troops) * 1.0 + 6; if (sp < me * .95) { if (d < tb) { tgt = { id: -1, x: Q.x, y: Q.y, pl: Q.id }; tb = d; } } else if (sp > me * 1.25 && d < 180) threat = Q; } }
    if (p.army) { threat = null; if (tgt && tb > 90) tgt = null; }
    if (threat && !tgt && p.fac !== 'undead') { const a = Math.atan2(p.y - threat.y, p.x - threat.x); const tx = clamp(p.x + Math.cos(a) * 220, 60, WW - 60), ty = clamp(p.y + Math.sin(a) * 220, 60, WH - 60); pathTo(p, tx, ty); p.state = 'flee'; p.tid = null; return; }
    if (tgt) { p.tid = tgt.pl ? null : tgt.id; p.tpl = tgt.pl || null; p.state = 'hunt'; pathTo(p, tgt.x, tgt.y); if (typeof warRally === 'function' && !tgt.pl && !p.army) warRally(p, tgt); return; }
    if (p.state === 'hunt' || p.state === 'flee') { p.state = 'idle'; p.tid = null; p.tpl = null; p.path = []; }
    if (p.state === 'idle' && p.pi >= p.path.length) {
      if (p.army) { /* идёт война: приказы отдаёт кампания */ } else if (p.kind === 'lord') { p.wait -= 1.2; if (p.wait <= 0) { const home = settleById(p.home), targets = G.settles.filter(s => s.fac === p.fac && s.kind !== 'camp'), prey = G.settles.filter(s => s.fac === 'player' && ownerHostile(s, p.fac)); const ru = ruinsFor(p.fac), d = ru.length && Math.random() < .5 ? pick(ru) : prey.length && Math.random() < .3 ? pick(prey) : pick(targets); if (d) { p.sid = d.id; p.state = 'travel'; pathTo(p, d.x, d.y); } else p.wait = 5; } }
      else if (p.kind === 'vassal') { p.wait -= 1.2; if (p.wait <= 0) vassalIdle(p); }
      else if (p.fac === 'undead') { p.wait -= 1.2; if (p.wait <= 0) undeadIdle(p); }
      else if (p.kind === 'bandit') { const c = settleById(p.home); const a = rnd(0, TAU), r = rnd(80, 340), tx = clamp((c ? c.x : p.x) + Math.cos(a) * r, 60, WW - 60), ty = clamp((c ? c.y : p.y) + Math.sin(a) * r, 60, WH - 60); if (!pathTo(p, tx, ty)) p.path = []; p.state = 'roam'; }
      else if (p.kind === 'caravan') { p.state = 'travel'; }
    }
  }
  if (p.state === 'hunt') { if (p.tpl) { const Q = G.players.find(q => q.id === p.tpl); if (!Q || Q.in || Q.away || Q.busy || Math.hypot(Q.x - p.x, Q.y - p.y) > 300) { p.state = 'idle'; p.path = []; p.tpl = null; } else if ((p.rp = (p.rp || 0) - dh) <= 0) { p.rp = .7; pathTo(p, Q.x, Q.y); } } else { const t = partyById(p.tid); if (!t || t.hide) { p.state = 'idle'; p.path = []; } else if ((p.rp = (p.rp || 0) - dh) <= 0) { p.rp = .7; pathTo(p, t.x, t.y); } } }
  if (p.pi < p.path.length) { const done = moveAlong(p, dh); if (done) { if (p.state === 'travel') { const s = settleById(p.sid); if (s && Math.hypot(s.x - p.x, s.y - p.y) < 40) { if (p.army) { p.state = 'idle'; p.path = []; p.pi = 0; p.arrived = true; return; } if (p.fac === 'undead') { undeadArrive(p, s); return; } if (s.fac === 'undead' && isNoble(p) && !nobleRetake(p, s)) { p.state = 'idle'; p.path = []; p.wait = rint(3, 8); if (troopCount(p.troops) < 10) G.parties.splice(G.parties.indexOf(p), 1); return; } if (p.kind === 'caravan') { if (s.fac !== 'bandit') { G.parties.splice(G.parties.indexOf(p), 1); return; } } if (s.fac === 'player') { p.state = 'idle'; p.path = []; p.wait = rint(4, 10); return; } if (p.kind === 'vassal') { vassalRest(p, s); return; } p.hide = true; p.wait = rint(5, 20); p.home = s.id; p.x = s.x; p.y = s.y; p.state = 'idle'; p.path = []; } } else if (p.state === 'roam') { p.state = 'idle'; p.wait = p.kind === 'vassal' ? rint(2, 6) : 0; } } }
  else if (p.state === 'travel' && p.kind === 'caravan') { const s = settleById(p.sid); if (s) pathTo(p, s.x, s.y); else G.parties.splice(G.parties.indexOf(p), 1); }
}
/* вассал без дела: половину времени идёт к своему лорду, иначе объезжает земли фракции (деревни и замки) */
function vassalIdle(p) {
  let L = p.lid != null ? partyById(p.lid) : null; if (!L || L.fac !== p.fac) { const ls = G.parties.filter(q => q.kind === 'lord' && q.fac === p.fac); L = ls.length ? pick(ls) : null; p.lid = L ? L.id : null; }
  if (L && Math.random() < .5) { const a = rnd(0, TAU), tx = clamp(L.x + Math.cos(a) * 45, 60, WW - 60), ty = clamp(L.y + Math.sin(a) * 45 + 20, 60, WH - 60); if (Math.hypot(L.x - p.x, L.y - p.y) > 80 && pathTo(p, tx, ty)) { p.state = 'roam'; return; } }
  const own = G.settles.filter(s => s.fac === p.fac && s.kind !== 'camp' && s.kind !== 'town'), near = own.sort((a, b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y)).slice(0, 6), d = near.length ? pick(near) : null;
  if (d) { p.sid = d.id; p.state = 'travel'; pathTo(p, d.x + rnd(-15, 15), d.y + 24); } else p.wait = 5;
}
function vassalRest(p, s) { // у своего поселения: стоит у стен несколько часов и добирает людей
  p.state = 'idle'; p.path = []; p.pi = 0; p.wait = rint(3, 8); p.home = s.id;
  const need = VAS_FULL * MK() - troopCount(p.troops); if (need > 0 && s.fac === p.fac) for (const a of genTroops(p.fac, Math.min(Math.ceil(need / MK()), rint(4, 10)), .55)) addT(p.troops, a.type, a.n);
}
function autoFight(a, b) {
  const sa = partyStr(a) * rnd(.8, 1.25), sb = partyStr(b) * rnd(.8, 1.25), w = sa >= sb ? a : b, l = w === a ? b : a, r = Math.min(sa, sb) / Math.max(sa, sb), wl = Math.min(.85, r * .85);
  if (w.fac === 'undead') undeadRaise(w, troopCount(l.troops) * UNDEAD.RAISE); // мертвецы поднимают павших
  for (const s of w.troops.slice()) { let d = 0; for (let i = 0; i < s.n; i++) if (Math.random() < wl) d++; remT(w.troops, s.type, d); }
  if (l.ruler && Math.random() < .75 && typeof rulerHome === 'function') { for (const s of l.troops.slice()) remT(l.troops, s.type, Math.floor(s.n * .55)); rulerHome(l); } // правитель чаще уходит раненым, чем гибнет
  else { const li = G.parties.indexOf(l); if (li >= 0) G.parties.splice(li, 1); }
  if (!w.troops.length || troopCount(w.troops) < 2) { const wi = G.parties.indexOf(w); if (wi >= 0) G.parties.splice(wi, 1); }
  w.state = 'idle'; w.path = []; w.pi = 0; w.cd = 3; w.gold += 20;
}
function hourTick() {
  G.hour++; if (G.hour >= 24) { G.hour = 0; G.day++; dayTick(); }
  for (const P of G.players) { if (P.away || P.busy === 'battle') continue; const heal = (P.in ? .035 : P.path.length && P.pi < P.path.length ? .006 : .014) * (1 + ((P.hero.int || 1) - 1) * .04 + perkFx(P.hero).heal); P.hero.hp = Math.min(1, P.hero.hp + heal); compsHeal(P, heal); }
  questsScoutTick(); undeadHour(); if (typeof warHour === 'function' && !SERVER) warHour();
  for (const s of G.settles) { if (s.kind === 'camp') { if (s.cleared) { s.respawn -= 1; if (s.respawn <= 0) respawnCamp(s); } continue; } s.rt += 1; if (s.rt >= 72) { s.rt = 0; genRecruits(s); } }
  for (const P of G.players) relWatch(P);
  if (G.hour % 3 === 0) assaultsTick();
  // спавны
  const bands = G.parties.filter(p => p.kind === 'bandit').length, cars = G.parties.filter(p => p.kind === 'caravan').length;
  if (G.hour % 6 === 0) { if (bands < (isEU() ? 10 : 5)) { const cs = G.settles.filter(s => s.kind === 'camp' && s.camp); if (cs.length && Math.random() < .5) { const c = pick(cs); mkParty('bandit', 'bandit', unitName('bandit') + ' и шайка', c.x + rnd(-30, 30), c.y + rnd(20, 40), genTroops('bandit', rint(9, 18), .4), { home: c.id }); } }
    if (cars < (isEU() ? 9 : 4) && Math.random() < .5) spawnCaravan(pick(G.settles.filter(s => s.kind === 'town' && REAL_F.includes(s.fac)))); }
  for (const f of worldF()) { const n = G.parties.filter(p => p.kind === 'vassal' && p.fac === f).length, hs = G.settles.filter(s => s.fac === f && s.kind !== 'camp'); if (n < (typeof warVass === 'function' && G.wars ? warVass(f) : vassalsPerF()) && G.hour === 6 && hs.length) spawnVassal(f, pick(hs), rint(VAS_NEW_MIN, VAS_NEW_MAX)); }
  if (!(G.clans && typeof clanRefill === 'function')) for (const f of worldF()) { const n = G.parties.filter(p => p.kind === 'lord' && p.fac === f).length; const hs = G.settles.filter(s => s.fac === f && s.kind !== 'village'); if (n < (typeof warLords === 'function' && G.wars ? warLords(f) : lordsPerF()) && G.hour === 12 && hs.length) { const h = pick(hs); mkParty('lord', f, lordName(f), h.x + 10, h.y + 20, genTroops(f, rint(LORD_NEW_MIN, LORD_NEW_MAX), .6), { home: h.id }); } }
}
function dayTick() { for (const P of G.players) if (!P.away && P.busy !== 'battle') playerDay(P); genQuests(); garrisonDay(); if (!SERVER) { compsDay(); crisisDay(); if (typeof warDay === 'function') warDay(); } } // спутники бродят по тавернам только в одиночной игре
function playerDay(P) {
  const cnt = troopCount(P.troops); eatProv(P, Math.max(0, Math.ceil(cnt / 6))); let wage = 0; for (const s of P.troops) wage += TROOPS[s.type].wage * s.n; wage = wageDay(P);
  if (P.gold >= wage) P.gold -= wage; else { P.gold = 0; compsUnpaid(P); if (cnt > 3 && Math.random() < .6) { const s = pick(P.troops); remT(P.troops, s.type, 1); logW('Не хватило денег на жалованье: ' + TROOPS[s.type].name.toLowerCase() + ' дезертировал.', 1, P); } }
  if (provOf(P) <= 0) { P.food = 0; if (cnt > 2 && Math.random() < .5) { const s = pick(P.troops); remT(P.troops, s.type, 1); logW('Отряд голодает: боец ушёл.', 1, P); } else logW('Закончилась провизия!', 1, P); }
  for (const q of P.quests.slice()) if (G.day > q.dl) { P.quests.splice(P.quests.indexOf(q), 1); P.rel[q.fac] = Math.max(-100, P.rel[q.fac] - 4); logW('Срок задания истёк: ' + questText(q), 1, P); }
  for (const f of REAL_F) P.rel[f] = P.rel[f] > 0 ? P.rel[f] - .1 : P.rel[f] < 0 ? Math.min(0, P.rel[f] + .25) : 0;
}
function wageDay(P) { let w = 0; for (const s of P.troops) w += TROOPS[s.type].wage * s.n; return Math.round((w / 3 + compWage(P)) * (1 - perkFx(P.hero).wage)); } // спутники берут своё жалованье целиком

/* ================= враждебность, гарнизоны и владения ================= */
const REAL_F = FAC_V[4]; // все фракции (на старой карте нужных нет, и их отряды и поселения просто не появляются)
const sCult = s => s.cult || s.fac; // культура поселения: облик, рекруты, рынок. При захвате не меняется
function relHostile(P, f) { return REAL_F.includes(f) && P.rel[f] < -20; }
function settleHostile(s, P) { return !!s && s.kind !== 'camp' && (s.fac === 'undead' || relHostile(P, s.fac)); }
function ownerOf(s) { return s && s.fac === 'player' ? G.players.find(q => q.id === s.owner) || null : null; }
function ownerHostile(s, f) { const O = ownerOf(s); return !!O && relHostile(O, f); }
// следим, когда фракция становится враждебной или мирится: сообщение в журнал и всплывашка
function relWatch(P) {
  for (const f of REAL_F) if (P.rel[f] === undefined) P.rel[f] = 0; // старые сохранения: новых фракций в них не было
  if (!P.hostF) { P.hostF = {}; for (const f of REAL_F) P.hostF[f] = relHostile(P, f); return; }
  for (const f of REAL_F) { const h = relHostile(P, f); if (!!P.hostF[f] === h) continue; P.hostF[f] = h;
    const msg = h ? 'Ты теперь враг ' + FACTIONS[f].gen + ': их лорды нападут, ворота их городов закрыты.' : 'Ты больше не враг ' + FACTIONS[f].gen + '.';
    logW(msg, h ? 1 : 3, P); if (!SERVER && typeof toast === 'function' && G.player === P) toast(msg); }
}
// война: отношения сразу падают до враждебных
function declareWar(P, f) { if (!REAL_F.includes(f)) return; P.rel[f] = Math.min(P.rel[f], -45); relWatch(P); }
function garCap(s) { return (s.kind === 'town' ? 130 : s.kind === 'castle' ? 210 : 0) * MK(); } // гарнизоны фракций пополняются до 80% этого
function garrisonOf(s) {
  if (!s.gar) { const n = s.kind === 'town' ? rint(85, 120) : s.kind === 'castle' ? rint(130, 175) : 0; s.gar = n ? genTroops(sCult(s), n, s.kind === 'castle' ? .75 : .62) : []; sortT(s.gar); }
  return s.gar;
}
/* Доход владения и содержание гарнизона. Доход: город 200, замок 100 в день, плюс по 15 за каждую деревню той же культуры в округе (до 450),
   с которой владение собирает подати. Гарнизон получает половину полевого жалованья (~0,8 золота за бойца). Город (~240) держит гарнизон в 110 бойцов
   (~90 в день; столько нужно, чтобы отбить лорда в 165 примерно в 2 случаях из 3) и даёт ~150 прибыли; замок (~140) с гарнизоном 80 — около 75. */
const GAR_WAGE = .5, INC_TOWN = 200, INC_CASTLE = 100, INC_VILLAGE = 15, INC_VR = 450;
function settleVillages(s) { return G.settles.filter(v => v.kind === 'village' && sCult(v) === sCult(s) && Math.hypot(v.x - s.x, v.y - s.y) < INC_VR).length; }
const INC_K = () => 1 + (MK() - 1) * .5; // при ×2 гарнизоны вдвое дороже, а подати прежние: растим их в полтора раза
function settleIncome(s) { return s.kind === 'town' || s.kind === 'castle' ? Math.round(((s.kind === 'town' ? INC_TOWN : INC_CASTLE) + settleVillages(s) * INC_VILLAGE) * INC_K() * (s.ruin > 0 ? .4 : 1)) : 0; } // руины после нежити: 40%, пока восстанавливаются
function garUpkeep(s) { let w = 0; for (const t of garrisonOf(s)) w += TROOPS[t.type].wage * t.n; return Math.round(w / 3 * GAR_WAGE); }
// раз в сутки: гарнизоны фракций пополняются, свои владения приносят доход
function garrisonDay() {
  for (const s of G.settles) { if (s.kind !== 'town' && s.kind !== 'castle') continue; const g = garrisonOf(s), n = troopCount(g);
    if (REAL_F.includes(s.fac) && n < garCap(s) * .8) { for (const a of genTroops(s.fac, Math.min(6, Math.round(garCap(s) * .8) - n), .6)) addT(g, a.type, a.n); sortT(g); }
    if (s.fac === 'player' && n < 6) { for (const a of genTroops(sCult(s), 1, .3)) addT(g, a.type, a.n); } }
  for (const P of G.players) { const own = G.settles.filter(s => s.fac === 'player' && s.owner === P.id); if (!own.length || P.away) continue;
    const inc = own.reduce((a, s) => a + settleIncome(s), 0), up = Math.round(own.reduce((a, s) => a + garUpkeep(s), 0) * (1 - perkFx(P.hero).wage)); P.gold += inc - up;
    if (P.gold < 0) { P.gold = 0; for (const s of own) { const g = garrisonOf(s); if (troopCount(g) > 6) { const t = pick(g); remT(g, t.type, Math.max(1, Math.round(t.n * .1))); } } logW('Казна пуста: гарнизоны без жалованья, часть бойцов разбежалась.', 1, P); }
    logW('Владения: доход +' + inc + ', гарнизоны −' + up + ' золота.', 3, P); }
}
// захват поселения игроком
function captureSettle(P, s) {
  s.cult = sCult(s); const was = s.fac; s.fac = 'player'; s.owner = P.id; s.board = []; s.gar = genTroops(s.cult, 4, .3); genRecruits(s);
  for (const p of G.parties.slice()) if (p.kind === 'lord' && p.hide && p.home === s.id) { G.parties.splice(G.parties.indexOf(p), 1); } // лорды, сидевшие внутри, бегут
  if (REAL_F.includes(was)) { P.rel[was] = Math.max(-100, P.rel[was] - 15); relWatch(P); }
  if (was === 'undead') { s.ruin = UNDEAD.RUIN_H; if (REAL_F.includes(s.ruinOf)) P.rel[s.ruinOf] = Math.min(100, P.rel[s.ruinOf] + 8); logW('Ты отбил ' + s.name + ' у мертвецов. Руины будут восстанавливаться 10 дней.', 3, P); }
  logW((s.kind === 'town' ? 'Город ' : 'Замок ') + s.name + ' теперь твой! Доход ' + settleIncome(s) + ' золота в день, гарнизон получает половину жалованья. Оставь там гарнизон (против лорда нужно около 110 бойцов), иначе его отобьют.', 3, P);
}
// лорды враждебных фракций штурмуют владения игрока (расчётом, без боя на поле)
function assaultsTick() {
  for (const s of G.settles) { if (s.fac !== 'player') continue; const O = ownerOf(s); if (!O) continue;
    const p = G.parties.find(q => q.kind === 'lord' && !q.hide && !q.lock && relHostile(O, q.fac) && Math.hypot(q.x - s.x, q.y - s.y) < 70); if (!p) continue;
    const g = garrisonOf(s), att = partyStr(p) * rnd(.8, 1.2), def = (strength(g) + 4) * 1.6 * rnd(.8, 1.2), r = Math.min(att, def) / Math.max(att, def);
    if (att > def) {
      for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * r * .5));
      s.fac = p.fac; s.owner = null; s.gar = genTroops(p.fac, 20, .5); p.hide = true; p.home = s.id; p.wait = rint(10, 30); genRecruits(s);
      logW(p.name + ' взял штурмом ' + s.name + '. Владение потеряно.', 1, O); if (!SERVER && typeof toast === 'function' && G.player === O) toast(p.name + ' захватил ' + s.name + '!');
    } else {
      for (const t of g.slice()) remT(g, t.type, Math.round(t.n * r * .45));
      const i = G.parties.indexOf(p); if (i >= 0) G.parties.splice(i, 1);
      logW('Гарнизон ' + s.name + ' отбил штурм: ' + p.name + ' разбит.', 3, O);
    }
  }
}
// гарнизон своего поселения: оставить или забрать бойцов
function garMove(P, s, type, n, toGar) {
  if (!s || s.fac !== 'player' || s.owner !== P.id) return 0; const from = toGar ? P.troops : garrisonOf(s), to = toGar ? garrisonOf(s) : P.troops, have = from.find(x => x.type === type); if (!have) return 0;
  n = Math.min(n, have.n); if (!toGar) n = Math.min(n, sizeCap(P.hero) - troopCount(P.troops)); if (toGar && from === P.troops) n = Math.min(n, troopCount(P.troops) - 1); if (n < 1) return 0;
  remT(from, type, n); addT(to, type, n); sortT(to); return n;
}
