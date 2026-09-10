defmodule Quorum.Sessions.Injection do
  @moduledoc """
  Two deterministic passes over a posted question, run before any model sees it.

  `normalize/1` strips the invisible characters an attacker uses to smuggle text
  past both a reader and a pattern match: zero-width spaces, bidi overrides, and
  control codes, with the body folded to NFC so look-alike forms match. Every
  question is normalized on the way in, so what's stored, shown, and fed to the
  AI is the same clean text.

  `suspicious?/1` looks for the blatant marks of an instruction aimed at an AI:
  the "ignore previous instructions" opener, a demand to print a system prompt,
  a chat-role marker smuggled into the body, a named jailbreak mode. It's a
  floor, not a judge: it runs without a model and without the per-room screen
  being on, so the obvious attempts are held even where nothing else would catch
  them. The fuzzy rest is what the model screen is for. Held, never refused, so
  the cost of a false positive is a presenter glancing at a question.
  """

  # Characters with no width or a direction of their own, plus the C0/C1 control
  # range. Tab, newline, and carriage return are kept; everything else here is
  # either invisible or a formatting override with no place in a typed question.
  @strip ~r/[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{007F}-\x{009F}\x{00AD}\x{180E}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{206F}\x{FEFF}]/u

  # Each pattern is written to want an instruction, not a mention: an imperative
  # verb or a literal marker, so a question *about* prompts or injection reads as
  # clean. The model screen carries the cases these miss.
  @patterns [
    # "ignore all previous instructions", "disregard the above", and kin.
    ~r/\b(ignore|disregard|forget|override|bypass)\b[^.\n]{0,30}\b(previous|prior|preceding|earlier|the above|all prior|all previous)\b/i,
    # A demand to divulge the system or hidden prompt.
    ~r/\b(reveal|show|print|repeat|output|leak|expose|display|tell me)\b[^.\n]{0,40}\b(system|hidden|initial|internal)\s+(prompt|instruction|instructions|message)\b/i,
    # A chat-role marker at the start of a line, standing in for a turn boundary.
    ~r/^\s{0,8}(system|assistant|developer)\s*:/im,
    ~r/\[\/?\s*(system|assistant|inst|instructions)\s*\]/i,
    # Model turn tokens pasted in whole.
    ~r/<\s*\/?\s*\|?\s*(im_start|im_end|endoftext)\s*\|?\s*>/i,
    # Named jailbreak modes.
    ~r/\bdo anything now\b/i,
    ~r/\bdeveloper mode\b/i
  ]

  @doc "Fold to NFC and strip invisible and direction-changing characters."
  def normalize(text) when is_binary(text) do
    folded =
      case :unicode.characters_to_nfc_binary(text) do
        binary when is_binary(binary) -> binary
        # Malformed input: leave the bytes be rather than raise on a posted form.
        _ -> text
      end

    String.replace(folded, @strip, "")
  end

  def normalize(other), do: other

  @doc "Whether the text carries the blatant mark of an instruction aimed at an AI."
  def suspicious?(text) when is_binary(text) do
    normalized = normalize(text)
    Enum.any?(@patterns, &Regex.match?(&1, normalized))
  end

  def suspicious?(_), do: false
end
