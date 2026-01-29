defmodule BaptismBackend.Manager.State do
  @moduledoc """
  Struct representing a baptism certificate profile.
  """

  alias BaptismBackend.Struct.Profile

  @derive {Jason.Encoder, only: [:profiles, :inference_url]}
  defstruct profiles: [],
            session_pid: nil,
            inference_url: nil

  @type t :: %__MODULE__{
          profiles: [Profile.t()],
          session_pid: pid() | nil,
          inference_url: String.t() | nil
        }

  def from_json(%{"profiles" => profiles} = json) do
    %__MODULE__{
      profiles: Enum.map(profiles, &Profile.from_json/1),
      inference_url: Map.get(json, "inference_url")
    }
  end
end
