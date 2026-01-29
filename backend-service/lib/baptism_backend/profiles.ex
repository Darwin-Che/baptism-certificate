defmodule BaptismBackend.Profiles do
  @moduledoc """
  The Profiles context for managing baptism certificate profiles.
  """

  @doc """
  Returns the list of profiles.
  """
  def list_profiles do
    # For now, return sample data. In production, this would fetch from a database or S3
    [
      %{
        id: "abc123",
        name_cn: "张三",
        name_pinyin: "Zhang San",
        birthday: "1990-01-01",
        baptism_date: "2024-03-15",
        status: :uploaded,
        original_image_url: nil,
        headshot_url: nil,
        paper_url: nil,
        certificate_url: nil,
        inserted_at: DateTime.utc_now()
      }
    ]
  end

  @doc """
  Gets a single profile.
  """
  def get_profile(id) do
    Enum.find(list_profiles(), &(&1.id == id))
  end

  @doc """
  Creates a profile from an uploaded file.
  """
  def create_profile(attrs \\ %{}) do
    # Generate a unique ID based on the file hash
    id = generate_id()

    profile = %{
      id: id,
      name_cn: attrs[:name_cn],
      name_pinyin: attrs[:name_pinyin],
      birthday: attrs[:birthday],
      baptism_date: attrs[:baptism_date],
      status: :uploaded,
      original_image_url: attrs[:original_image_url],
      headshot_url: nil,
      paper_url: nil,
      certificate_url: nil,
      inserted_at: DateTime.utc_now()
    }

    {:ok, profile}
  end

  @doc """
  Updates a profile.
  """
  def update_profile(id, attrs) do
    profile = get_profile(id)

    if profile do
      updated_profile = Map.merge(profile, attrs)
      {:ok, updated_profile}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns profiles that need extraction (status: uploaded).
  """
  def list_unextracted_profiles do
    list_profiles()
    |> Enum.filter(&(&1.status == :uploaded))
  end

  @doc """
  Sends profiles to the inference server for extraction.
  """
  def extract_profiles(profile_ids) do
    # In production, this would call the inference service API
    # For now, just update the status
    Enum.map(profile_ids, fn id ->
      update_profile(id, %{status: :extracted})
    end)
  end

  @doc """
  Generates a certificate for a profile.
  """
  def generate_certificate(id) do
    # In production, this would generate the certificate
    update_profile(id, %{
      status: :generated,
      certificate_url: "/certificates/#{id}.pdf"
    })
  end

  @doc """
  Marks a profile as reviewed.
  """
  def mark_reviewed(id) do
    update_profile(id, %{status: :reviewed})
  end

  @doc """
  Gets the display name for a profile.
  """
  def display_name(profile) do
    profile.name_cn || profile.name_pinyin || profile.id
  end

  @doc """
  Returns the status badge color.
  """
  def status_color(status) do
    case status do
      :uploaded -> "badge-warning"
      :extracted -> "badge-info"
      :generated -> "badge-success"
      :reviewed -> "badge-primary"
      _ -> "badge-ghost"
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end
end
