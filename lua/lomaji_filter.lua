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

local function filter(input, env)
  local prism = env and env.engine.schema.config:get_string("translator/prism")
  local tone_pattern = prism == "lomaji_nature" and "[1-9y%-]" or "[qwzxdfv1-9y%-]"
  local candidates = {}
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
      local output = cand
      if text ~= "" and text ~= cand.text then
        output = ShadowCandidate(cand, cand.type, text, cand.comment)
      end
      candidates[#candidates + 1] = {
        candidate = output,
        finish = cand._end,
        phrase = sentence ~= nil or text:find("-", 1, true) ~= nil
          or text:find("%s") ~= nil,
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
    if a.phrase ~= b.phrase then return not a.phrase end
    return a.index < b.index
  end)
  for _, item in ipairs(candidates) do
    yield(item.candidate)
  end
end

return filter
