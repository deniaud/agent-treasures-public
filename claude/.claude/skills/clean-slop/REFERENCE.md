# Reference: Neuroslop Stop-Words & Patterns

Exhaustive catalogue of LLM stylistic artifacts in Russian and English, with native replacements.
Use this file as a lookup. When in doubt: cut, don't soften.

> **Прежде чем заменять — проверь источник.** Все колонки "Replacement" с конкретикой ("first/largest/+X%", "конкретные тонны CO₂", "версия/дата", "ускорил X с N до M", "наняли N человек в X") применяй **только если эти данные есть в исходном тексте**. Нет данных — выбирай нейтральную опцию из той же ячейки (`delete`, общее слово) или удаляй фразу. Подставлять цифры, имена, версии и метрики "по смыслу" запрещено: это галлюцинация под видом конкретики. Лучше пустота, чем правдоподобная ложь.

---

## 1. Hedging openers & filler transitions

| Banned (RU) | Banned (EN) | Replacement |
|---|---|---|
| Важно отметить, что | It is important to note that | (delete; state fact directly) |
| Стоит заметить | It's worth mentioning | (delete) |
| Следует учитывать / Следует отметить | It should be considered / noted | (delete) |
| Нельзя не упомянуть | One cannot fail to mention | (delete) |
| Подводя итог / В заключение | In conclusion / To wrap up | (delete; stop sharp) |
| Таким образом | Thus / Therefore | (delete or "так что") |
| Более того / Кроме того | Furthermore / Moreover / Additionally | "также" / "ещё" / (delete) |
| В современном мире / В современную эпоху | In today's world / In the modern era | name the actual year/decade |
| В сегодняшнюю цифровую эпоху | In today's digital age | (delete) |
| В контексте … | In the context of … | "при …" / "в …" |

## 2. Puffery — artificial drama and "significance"

| Banned (RU) | Banned (EN) | Replacement |
|---|---|---|
| Ключевая роль / Ключевой момент | Pivotal / Key role / Key moment | (delete; cite the role itself) |
| Неоценимый вклад | Invaluable contribution | concrete number or output |
| Революционный / Прорывной | Revolutionary / Groundbreaking | "новый", метрика |
| Трансформационный / Преобразующий | Transformative | "меняет X на Y" |
| Поворотный | Pivotal / Turning point | date or event |
| Является свидетельством / Свидетельствует о | Is a testament to / Stands as a reminder | (delete; show, don't claim) |
| Яркий гобелен / Калейдоскоп / Симфония | Vibrant tapestry / Kaleidoscope / Symphony | (delete) |
| Беспрецедентный | Unprecedented | first/largest/+X% |
| Неизгладимый след / Непреходящее наследие | Indelible mark / Enduring legacy | (delete) |
| Истинная суть | True essence | "это" |
| Углубляться (в тему) | Delve into | "разобрать", "посмотреть" |
| Подчёркивает важность / Высвечивает | Underscores / Highlights the importance | (delete; just state the fact) |
| Выступает в качестве / Служит | Serves as / Stands as | "—" or "это" |
| Формирующий ландшафт | Shaping the landscape | (delete) |
| Глубоко укоренившийся | Deeply rooted | "давний" / date |
| Многогранный / Многоаспектный | Multifaceted | "сложный" |
| Надёжный (как калька robust) | Robust | "устойчивый к X", метрика |
| Масштабируемый (как пустое слово) | Scalable | конкретная нагрузка |
| Передовой / Современный (без уточнения) | Cutting-edge / State-of-the-art | модель/версия/дата |
| Комплексный / Всеобъемлющий | Comprehensive | перечень охвата |
| Непоколебимый / Неизменная приверженность | Unwavering / Steadfast commitment | (delete) |

## 3. Corporate / CSR / press-release tone

| Banned | Replacement |
|---|---|
| В условиях / В связи с этим | "из-за" / "потому что" |
| Задействовать | "использовать" |
| Синергия / Synergy | "взаимодействие" / (delete) |
| Оптимизация процессов | "ускорил X с N до M" |
| Динамично развивающийся | (delete) |
| Неизменная приверженность экологической устойчивости | (delete entirely) |
| Снижение углеродного следа | конкретные тонны CO₂ |
| Повышение операционной эффективности | конкретные показатели |
| Содействие развитию местного сообщества | "наняли N человек в X" |
| Уютно расположившийся / Nestled | "в X километрах от Y" |
| Idealный шлюз / Ideal gateway | (delete) |
| Может похвастаться / Boasts a | "есть X" / "имеет X" |
| Vibrant / Яркий | concrete description |
| Profound / Глубокий | (delete unless measurable) |
| Renowned / Известный | "получил премию X" / (delete) |
| Leverage | "использовать" |
| Paradigm shift | (delete; describe change) |
| Elevate | "улучшить" / "поднять" |
| Navigate (in metaphor sense) | "пройти" / "разобраться с" |

## 4. Balanced parasite constructions (kill on sight)

- `Не только …, но и …` → keep one side, drop the balance
- `Не просто …, а …` → name the actual thing
- `Это не X, это Y` → just say what it is
- `Not just X, but also Y` → same as above
- `Not X, but Y` → same as above
- `На стыке … и …` (in metaphor sense) → "сочетает X с Y"

## 5. Weasel-words & false attribution

Banned blanket phrases:
- "Некоторые критики / эксперты утверждают"
- "Несколько изданий отмечают"
- "Исследователи и защитники природы считают"
- "Широко интерпретируется как"
- "Поддерживается множеством экспертов"
- "Some critics argue / Several outlets report / Researchers believe"
- "Has received independent coverage"
- "Was profiled in leading publications"
- "Widely cited in The New York Times, BBC, …" (without quote)

Rule: снимай размытую атрибуцию ("некоторые эксперты", "несколько изданий"), но **сохрани сам факт**, если он проверяем общими знаниями или нейтрален. Удаляй утверждение целиком только когда без анонимной атрибуции оно превращается в бездоказательное мнение (оценка, прогноз, спорная интерпретация). Never invent attribution. Если автор исходного текста сам ссылается на конкретный источник — оставь ссылку.

## 6. Conditional modality (covers algorithmic uncertainty)

Snimat' modal'nost' можно **только когда "может / возможно / по-видимому" — это алгоритмическая вата перед уверенным фактом** ("Технология может быть полезна для X" в контексте, где она точно используется для X).

**Сохраняй модальность**, если она отражает реальную эпистемическую неопределённость: прогноз, гипотеза, условный сценарий, научная осторожность, юридическая/медицинская формулировка. Превращать гипотезу в утверждение ("может повлиять" → "влияет") запрещено — это фальсификация.

| Banned (when hedge is hollow) | Replacement | Keep when |
|---|---|---|
| Может повлиять на X | состояние из исходника: "влияет / влияния нет" / delete | автор намеренно фиксирует неопределённость влияния |
| Может стать | "становится" / delete | прогноз с неизвестным исходом |
| Может быть полезным для | "полезен при X" / delete | рекомендация с условиями применимости |
| Может рассматриваться как | "это" / delete | альтернативная интерпретация, не консенсус |

## 7. Formulaic closers (Outline-like conclusions)

Banned wrap-up structures:
- "Несмотря на эти проблемы / трудности / вызовы, X имеет большие перспективы…"
- "В будущем X продолжит развиваться…"
- "Проблемы и перспективы / Взгляд в будущее"
- "Despite these challenges, X is poised to…"
- "Looking ahead / Future Outlook"

Replacement strategy: end on a verifiable fact, an unresolved tension, or simply stop. **Не путать со снятием авторского вывода.** Если в исходнике финал несёт реальный синтез, оценку или прогноз — сохрани его, перепиши без формульной обёртки ("Несмотря на… имеет перспективы" → конкретный тезис автора). Резать только пустую риторическую рамку, не содержание.

## 8. Rule of three

Watch for symmetric **rhetorical** triples — стилистические перечисления для красоты, где три абстрактных существительных-нормализации идут симметричной обоймой ("для повышения эффективности, снижения затрат и улучшения качества"). Default to:
- one strong collective noun, or
- a 2-item or 4-item asymmetric list, or
- prose with sentence rhythm variation

**Не применять правило к фактическим перечням.** Если три элемента — это конкретные сущности из исходника (три компании, три этапа, три причины), оставь триплет как есть. Не выдумывай четвёртый пункт ради асимметрии и не вычёркивай один элемент ради двойки.

Each text section should have at most ONE *rhetorical* triple, and only if rhetorically earned. Фактические триплеты не нормируются.

## 9. Negative parallelisms & copulative avoidance

Anti-patterns:
- "Не X, а Y" / "Не только X, но и Y" → see §4
- "Сохранение этого вида важно не только для разнообразия, но и для культуры" → "Этот вид важен для разнообразия и культуры" (or pick one)
- "Этот город служит центром / выступает в качестве центра" → "Этот город — центр" / "Это центр"
- "Эта технология является основой" (acceptable) vs "Эта технология выступает в качестве основы" (banned)

## 10. Formatting artifacts

### Markdown abuse
- `**bold inside paragraph**` for emphasis → delete `**`, keep prose
- `*italic for "Wired"*` and other source names → drop italic
- `**Subheader:** body in a list item` (Inline-header vertical lists) → fold into running prose

### Punctuation
- Em-dash `—` overuse как риторический приём (вставки, заменители запятой, "элегантные" паузы): cut by ~80%. Use comma, period or colon instead. **Не сокращай грамматически обязательное тире**: связка "подлежащее — сказуемое" в русском ("Москва — столица России"), тире в неполных предложениях ("Я — за"), тире в диалогах, тире в перечнях после обобщающего слова. Это не риторический приём, а грамматика.
- Curly quotes `“ ” ‘ ’` → straight `" "` `' '`
- En-space `U+2002`, NBSP `U+00A0` between regular words → regular space `U+0020`
- Capital letter after colon (mid-sentence) → lowercase, unless proper noun
- Triple punctuation, suspension dots overuse → standard `…` or single period

### RAG / chat artifacts to purge
Regex-target list: `turn\d+search\d+`, `oaicite`, `oai_citation`, `contentReference`, `\+1` floating tokens, `grok_card`, `attached_file`, `utm_source=`, `utm_medium=`, `utm_campaign=`, `ref=chatgpt`, broken citation brackets `【】`, `:contentReference[…]`, knowledge-cutoff disclaimers ("as of my last training", "I cannot access real-time information"), meta-instructions ("In this section we will discuss…", "If you want to add this to the article…"), apology preludes ("I'd be happy to help…", "Certainly! Here's…").

## 11. AI red-flag word groups (English source, calques bleed into Russian)

| Group | Tokens |
|---|---|
| Drama/metaphor | transformative, revolutionary, game-changer, unleash, unlock, testament, beacon, tapestry, symphony, journey, landscape, ecosystem (metaphor) |
| Vague evaluatives | robust, scalable, cutting-edge, comprehensive, pivotal, unwavering, multifaceted, holistic, seamless, intricate, dynamic, vibrant |
| Corporate buzzwords | leverage, synergy, paradigm shift, elevate, navigate, foster, empower, streamline, optimize, scale, drive |
| Mechanical transitions | furthermore, moreover, additionally, in conclusion, importantly, notably, indeed, however (overused), ultimately |

**Контекст важен.** "Vague evaluatives" (robust, scalable, comprehensive, dynamic, seamless) допустимы в техническом контексте, если рядом стоит конкретика — нагрузка, версия, метрика, перечень — или термин используется как устоявшийся в предметной области ("robust regression", "scalable architecture"). Запрещены только в маркетинговой/декоративной роли без подкрепления.

Native replacements: impactful → major; start using → use; access → get; proof → evidence; guide → handbook; mix → blend; strong → robust-OK in technical context only; new → new; full → full; key → main (still risky); steady → stable; complex → complicated.

---

## Severity rubric for self-audit

After rewriting, scan output and rate density:
- **0 hits** of any §1-§9 entries: ship.
- **1-3 hits**: rewrite affected sentences.
- **4+ hits**: full second pass.

If `scripts/detect-slop.sh` is available, treat its output as authoritative.
