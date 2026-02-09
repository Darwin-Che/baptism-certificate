defmodule BaptismBackend.Struct.Profile do
  @moduledoc """
  Struct representing a baptism certificate profile.
  """

  @derive {Jason.Encoder, only: [:id, :name_cn, :name_pinyin, :birthday, :baptism_date, :status]}
  defstruct [
    :id,
    :name_cn,
    :name_pinyin,
    :birthday,
    :baptism_date,
    :status
  ]

  @type status :: :uploaded | :extracted | :generated | :reviewed

  @type t :: %__MODULE__{
          id: String.t(),
          name_cn: String.t() | nil,
          name_pinyin: String.t() | nil,
          birthday: Date.t() | nil,
          baptism_date: Date.t() | nil,
          status: status()
        }

  def from_json(map) do
    %__MODULE__{
      id: map["id"],
      name_cn: map["name_cn"],
      name_pinyin: map["name_pinyin"],
      birthday: parse_date(map["birthday"]),
      baptism_date: parse_date(map["baptism_date"]),
      status: parse_status(map["status"])
    }
  end

  def merge(%__MODULE__{} = profile, attrs) when is_map(attrs) do
    Enum.reduce(attrs, profile, fn
      {"name_cn", value}, acc -> %{acc | name_cn: value}
      {"name_pinyin", value}, acc -> %{acc | name_pinyin: value}
      {"birthday", value}, acc -> %{acc | birthday: parse_date(value)}
      {"baptism_date", value}, acc -> %{acc | baptism_date: parse_date(value)}
      _, acc -> acc
    end)
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_status("uploaded"), do: :uploaded
  defp parse_status("extracted"), do: :extracted
  defp parse_status("generated"), do: :generated
  defp parse_status("reviewed"), do: :reviewed

  @doc """
  Normalize name_pinyin to ensure words are separated by comma+space.
  Converts "Sun JianFen" -> "Sun, JianFen"
  Converts "Sun Jian Fen" -> "Sun, JianFen" (combines words after first)
  Converts "Sun,JianFen" -> "Sun, JianFen"
  """
  defp normalize_name_pinyin(nil), do: nil
  defp normalize_name_pinyin(""), do: ""
  defp normalize_name_pinyin(name) do
    name
    |> String.trim()
    # First normalize any existing commas to have consistent spacing
    |> String.replace(~r/,\s*/, ", ")
    # Split by comma or space to get all parts
    |> then(fn n ->
      cond do
        # If already has comma, just ensure proper spacing (already done above)
        String.contains?(n, ",") ->
          n

        # If has spaces, split and recombine: first word, then rest without spaces
        String.contains?(n, " ") ->
          parts = String.split(n, " ", trim: true)
          case parts do
            [first | rest] when rest != [] ->
              # Combine all words after the first into one word
              given_name = Enum.join(rest, "")
              "#{first}, #{given_name}"
            _ ->
              n
          end

        # No comma or space, return as-is
        true ->
          n
      end
    end)
  end

  def apply_extraction_result(%__MODULE__{} = profile, %{
        "parse_ocr_result" => %{
          "name_cn" => name_cn,
          "name_pinyin" => name_pinyin,
          "birthday" => birthday,
          "baptism_date" => baptism_date
        }
      }) do
    %__MODULE__{
      profile
      | name_cn: name_cn,
        name_pinyin: normalize_name_pinyin(name_pinyin),
        birthday: parse_date(birthday),
        baptism_date: parse_date(baptism_date)
    }
  end
end
