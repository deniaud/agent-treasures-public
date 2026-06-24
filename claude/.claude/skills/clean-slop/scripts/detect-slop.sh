#!/usr/bin/env bash
# detect-slop.sh — enumerate LLM "neuroslop" markers in a text file.
# Usage: detect-slop.sh <file>
#        detect-slop.sh -      # read from stdin
# Exit code: 0 = clean, 1 = violations found, 2 = bad invocation.

set -u

if [ $# -lt 1 ]; then
  echo "usage: detect-slop.sh <file|->" >&2
  exit 2
fi

src="$1"
if [ "$src" = "-" ]; then
  tmp="$(mktemp)"
  cat > "$tmp"
  src="$tmp"
  trap 'rm -f "$tmp"' EXIT
elif [ ! -f "$src" ]; then
  echo "file not found: $src" >&2
  exit 2
fi

total=0

scan() {
  local label="$1"; shift
  local pattern="$1"; shift
  local hits
  hits=$(grep -inE "$pattern" "$src" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    local count
    count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    total=$((total + count))
    echo "── $label ($count) ──"
    printf '%s\n' "$hits"
    echo
  fi
}

# 1. Hedging openers
scan "Hedging openers (RU)" \
  '(важно отметить|стоит заметить|следует учитывать|следует отметить|нельзя не упомянуть|подводя итог|в заключение|таким образом|более того|кроме того|в современном мире|в современную эпоху|в сегодняшнюю цифровую эпоху)'

scan "Hedging openers (EN)" \
  '\b(it is important to note|furthermore|moreover|additionally|in conclusion|to wrap up|it'\''s worth (noting|mentioning)|notably|indeed|ultimately)\b'

# 2. Puffery
scan "Puffery (RU)" \
  '(ключев(ая|ой) (роль|момент)|неоценимый вклад|революционн|трансформационн|преобразующ|поворотн|является свидетельств|свидетельствует о|гобелен|калейдоскоп|симфония|беспрецедентн|неизгладим|непреходящ[ие]|истинная суть|углубляться|подчёркивает важност|подчеркивает важност|формирующий ландшафт|глубоко укоренивш|непоколебим|многогранн|многоаспектн)'

scan "Puffery (EN)" \
  '\b(delve|underscores?|pivotal|testament|tapestry|symphony|beacon|unleash|unlock|transformative|revolutionary|game-changer|groundbreaking|unprecedented|indelible|enduring legacy|robust|scalable|cutting-edge|state-of-the-art|comprehensive|unwavering|multifaceted|holistic|seamless|vibrant)\b'

# 3. CSR / corporate
scan "Corporate / CSR" \
  '(в условиях|в связи с этим|задействовать|синергия|оптимизация процессов|динамично развивающ|неизменная приверженность|уютно расположивш|может похвастаться|leverage|synergy|paradigm shift|elevate|navigate|foster|empower|streamline|nestled|boasts a|renowned|profound|снижени[ея] углеродного следа|повышени[ея] операционной эффективности|содействи[ея] развитию|приверженность экологической)'

# 4. Balanced parasites
scan "Balanced parasites" \
  '(не только[^.]*но и|не просто[^.]*а |это не [а-яё]+, это |\bnot just [^.]+, but also|\bnot [^.,]+, but )'

# 5. Weasel-words
scan "Weasel-words" \
  '(некоторые (эксперты|критики|исследователи|аналитики)|несколько (изданий|источников|экспертов)|широко (интерпретируется|освещалось|цитировалось)|поддерживается множеством|исследователи и (защитники|эксперты) считают|some (experts|critics|researchers) (say|argue|believe)|several (outlets|sources) (report|note)|widely (cited|reported|covered)|has received independent coverage|was profiled in)'

# 6. Conditional modality
scan "Conditional hedging" \
  '(может (повлиять|стать|быть полезн|рассматриваться)|may (impact|become|prove (useful|beneficial)))'

# 7. Formulaic closers
scan "Formulaic closer" \
  '(несмотря на (эти |все )?(проблемы|трудности|вызовы|сложности)[^.]*перспектив|в будущем [а-яё]+ продолж|проблемы и перспективы|взгляд в будущее|despite (these|the) challenges|looking ahead|future outlook)'

# 8. Copulative avoidance
scan "Copulative avoidance" \
  '(выступает в качестве|служит (примером|основой|центром|шлюзом)|serves as|stands as)'

# 9. Markdown / format artifacts
scan "Inline-header lists" \
  '^[[:space:]]*[-*][[:space:]]+\*\*[^*]+:\*\*'

scan "Mid-paragraph bold" \
  '[а-яёa-z][.,;:]?[[:space:]]+\*\*[^*]+\*\*[[:space:]]+[а-яёa-z]'

scan "Curly quotes / fancy punct" \
  '[“”‘’«»]'

scan "Em-dash density" \
  '—[^—]{1,80}—'

# 10. RAG / chat artifacts
scan "RAG / chat artifacts" \
  '(turn[0-9]+search[0-9]+|oaicite|oai_citation|contentReference|grok_card|attached_file|utm_(source|medium|campaign)=|ref=chatgpt|【[^】]*】|:contentReference)'

scan "Knowledge-cutoff disclaimers" \
  '(as of my (last )?(training|knowledge cutoff)|i cannot access real-time|на момент моего обучения|по состоянию на дату моего обучения)'

# 11. Invisible humanizer artifacts
if grep -qP '[\x{2002}\x{2003}\x{2009}\x{200B}]' "$src" 2>/dev/null; then
  count=$(grep -cP '[\x{2002}\x{2003}\x{2009}\x{200B}]' "$src")
  total=$((total + count))
  echo "── Invisible spaces (U+2002/2003/2009/200B) ($count lines) ──"
  echo "  (run: sed -i 's/[\\xe2\\x80\\x82\\xe2\\x80\\x83\\xe2\\x80\\x89\\xe2\\x80\\x8b]/ /g' '$src')"
  echo
fi

echo "════════════════════════════════════════"
if [ $total -eq 0 ]; then
  echo "result: clean (0 hits)"
  exit 0
elif [ $total -le 3 ]; then
  echo "result: minor — $total hit(s), targeted rewrite"
  exit 1
else
  echo "result: heavy slop — $total hit(s), full rewrite required"
  exit 1
fi
