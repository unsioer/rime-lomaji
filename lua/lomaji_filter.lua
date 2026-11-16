-- Run before the POJ/capital simplifiers, while text is still in Tai-lo.
local base_letters = {}
for base, variants in pairs({
  a = "áàâǎāÁÀÂǍĀ", e = "éèêěēÉÈÊĚĒ", i = "íìîǐīÍÌÎǏĪ",
  o = "óòôǒōőÓÒÔǑŌŐ", u = "úùûǔūűÚÙÛǓŪŰ",
  m = "ḿḾ", n = "ńǹňŃǸŇ",
}) do
  for _, codepoint in utf8.codes(variants) do base_letters[codepoint] = base end
end
local tone_marks = {
  [0x300] = true, [0x301] = true, [0x302] = true, [0x304] = true,
  [0x30B] = true, [0x30C] = true, [0x30D] = true,
}

local function canonical_letters(text)
  -- The schema accepts these alternative spellings, with equal letter counts.
  return text:lower():gsub("ch", "ts"):gsub("oa", "ua"):gsub("oe", "ue")
end

local function restore_boundaries(text, preedit, tone_pattern)
  -- Learned phrases lose Sentence.entrys but retain their input-code boundaries
  -- in preedit. Only restore separators if the ENTIRE spelling aligns.
  local parts = {}
  for token in (preedit or ""):gmatch("%S+") do
    local spelling = token:lower()
    if #spelling > 1 then spelling = spelling:gsub(tone_pattern, "") end
    if spelling == "" or spelling:find("[^a-z]") then return text end
    parts[#parts + 1] = canonical_letters(spelling)
  end
  if #parts < 2 then return text end

  local letters, ends = {}, {}
  for pos, codepoint in utf8.codes(text) do
    local char = utf8.char(codepoint)
    local base = base_letters[codepoint]
    if codepoint < 128 and char:match("[A-Za-z]") then base = char:lower() end
    if base then
      letters[#letters + 1] = base
      ends[#letters] = pos + #char - 1
    elseif tone_marks[codepoint] and #letters > 0 then
      -- Include NFD combining marks with their vowel, never after a new hyphen.
      ends[#letters] = pos + #char - 1
    elseif char ~= "-" then
      return text
    end
  end
  if canonical_letters(table.concat(letters)) ~= table.concat(parts) then return text end

  local result, previous, offset = {}, 1, 0
  for i = 1, #parts - 1 do
    offset = offset + #parts[i]
    local last = ends[offset]
    if not last then return text end
    if text:sub(last + 1, last + 1) ~= "-" then
      result[#result + 1] = text:sub(previous, last) .. "-"
      previous = last + 1
    end
  end
  result[#result + 1] = text:sub(previous)
  return table.concat(result)
end

local function join_entries(sentence)
  local text = ""
  for _, entry in ipairs(sentence.entrys) do
    local part = entry.text
    if part ~= "" then
      -- Preserve explicit separators (including light-tone --).
      if text ~= "" and text:sub(-1) ~= "-" and part:sub(1, 1) ~= "-" then
        text = text .. "-"
      end
      text = text .. part
    end
  end
  return text
end

local function is_romanized(text)
  local has_letter = false
  for _, cp in utf8.codes(text) do
    if base_letters[cp] or (cp < 128 and utf8.char(cp):match("[A-Za-z]")) then
      has_letter = true
    elseif not tone_marks[cp] and cp ~= 45 then
      return false
    end
  end
  return has_letter
end

local function follows_selected_syllable(cand, env)
  local context = env and env.engine.context
  if not context or cand._start == 0 then return false end
  local segments = context.composition:toSegmentation():get_segments()
  for _, seg in ipairs(segments) do
    if seg._end == cand._start and seg._start < seg._end
        and (seg.status == "kSelected" or seg.status == "kConfirmed") then
      local previous = seg:get_selected_candidate()
      return previous ~= nil and previous.text:sub(-1) ~= "-"
        and is_romanized(previous:get_genuine().text)
    end
  end
  return false
end

-- A numeric tone terminates its syllable. Rime's sentence scorer can instead
-- prefer u + í-ta̍t over uí + ta̍t because the former contains a fixed phrase.
-- Build the fully specified spelling from dictionary entries, retaining genuine
-- syllable codes and language so normal Rime learning still works.
local function exact_tone_phrase(cand, env)
  local context = env and env.engine.context
  if not context or not Memory then return nil end
  local raw = context.input:sub(cand._start + 1, cand._end)
  local parts, separators, position = {}, {}, 1
  while position <= #raw do
    local first, last, spelling = raw:find("([A-Za-z]+[1-9])", position)
    if first ~= position then return nil end
    parts[#parts + 1] = spelling
    position = last + 1
    local separator = raw:match("^([y%-]*)", position) or ""
    separators[#parts] = separator:gsub("y", "-")
    position = position + #separator
  end
  if #parts < 2 then return nil end
  if not env.memory then
    env.memory = Memory(env.engine, env.engine.schema, "translator")
  end
  -- Use the value Code returned by DictEntry, rather than the shared-pointer
  -- Code() constructor (older librime-lua setters do not accept that wrapper).
  local original = cand:get_genuine():to_phrase()
  if not original then return nil end
  local syllable_count = 0
  for _, spelling in ipairs(env.memory:decode(original.code)) do
    -- Fixed phrases use a single Rime code containing hyphens.
    for _ in spelling:gmatch("[^%s%-]+") do syllable_count = syllable_count + 1 end
  end
  if syllable_count <= #parts then return nil end
  local text, code = {}, DictEntry().code
  for i, spelling in ipairs(parts) do
    local entry
    if env.memory:dict_lookup(spelling, false, 0) then
      for item in env.memory:iter_dict() do
        if #env.memory:decode(item.code) == 1 and is_romanized(item.text) then
          entry = item
          break
        end
      end
    end
    if not entry then return nil end
    text[#text + 1] = entry.text
    if i < #parts then text[#text + 1] = separators[i] ~= "" and separators[i] or "-" end
    for syllable in entry.code:print():gmatch("%d+") do code:push(tonumber(syllable)) end
  end
  if separators[#parts] ~= "" then text[#text + 1] = separators[#parts] end
  local entry = DictEntry()
  entry.text, entry.code = table.concat(text), code
  entry.preedit = table.concat(parts, " ")
  local phrase = Phrase(env.memory, "phrase", cand._start, cand._end, entry)
  phrase.quality = cand.quality
  return phrase:toCandidate()
end

local function filter(input, env)
  local prism = env and env.engine.schema.config:get_string("translator/prism")
  local tone_pattern = prism == "lomaji_nature" and "[1-9y%-]" or "[qwzxdfv1-9y%-]"
  local candidates = {}
  local exact_added = false
  for cand in input:iter() do
    local genuine = cand:get_genuine()
    local kind = genuine.type
    if kind == "phrase" or kind == "user_phrase" or kind == "completion"
        or kind == "sentence" then
      -- Sentence components carry the real boundaries; UTF-8 character count
      -- cannot identify syllables in romanized text with combining tone marks.
      local sentence = genuine:to_sentence()
      local text = sentence and join_entries(sentence) or cand.text
      text = restore_boundaries(text, cand.preedit, tone_pattern)
      if prism == "lomaji_nature" and not exact_added and (sentence or kind == "user_phrase") then
        local exact = exact_tone_phrase(cand, env)
        if exact and exact.text ~= text then
          exact_added = true
          local exact_text = exact.text
          if follows_selected_syllable(exact, env) then exact_text = "-" .. exact_text end
          candidates[#candidates + 1] = {
            candidate = ShadowCandidate(exact, exact.type, exact_text, exact.comment),
            finish = exact._end, phrase = true, exact = true, index = #candidates + 1,
          }
        end
      end
      local phrase = sentence ~= nil or text:find("-", 1, true) ~= nil
        or text:find("%s") ~= nil
      -- Rime concatenates separately selected segments verbatim. Supply their
      -- boundary in the shadow only; keep the dictionary candidate for learning.
      if text:sub(1, 1) ~= "-" and is_romanized(text)
          and follows_selected_syllable(cand, env) then
        text = "-" .. text
      end
      local output = cand
      if text ~= "" and text ~= cand.text then
        output = ShadowCandidate(cand, cand.type, text, cand.comment)
      end
      candidates[#candidates + 1] = {
        candidate = output,
        finish = cand._end,
        phrase = phrase,
        index = #candidates + 1,
      }
    else
      yield(cand)
    end
  end
  -- Never promote a short prefix over a candidate covering the whole input.
  -- Only prefer syllables when both candidates consume the same input span.
  table.sort(candidates, function(a, b)
    if a.finish ~= b.finish then return a.finish > b.finish end
    if a.exact ~= b.exact then return a.exact == true end
    if a.phrase ~= b.phrase then return not a.phrase end
    return a.index < b.index
  end)
  for _, item in ipairs(candidates) do
    yield(item.candidate)
  end
end

return {
  func = filter,
  fini = function(env)
    if env.memory then env.memory:disconnect(); env.memory = nil end
  end,
}
