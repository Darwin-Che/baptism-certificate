defmodule BaptismBackend.S3Storage do
  @moduledoc """
  Module for handling S3 storage operations.
  """
  alias BaptismBackend.Manager.State

  require Logger

  @spec fetch_state() :: {:ok, State.t()} | {:error, any()}
  def fetch_state do
    case bucket_name()
         |> ExAws.S3.get_object("manager_state.json")
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body |> Jason.decode!() |> State.from_json()}

      {:error, {:http_error, 404, _}} ->
        # If the state file does not exist, return an empty state
        {:ok, %State{profiles: [], session_pid: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec save_state(State.t()) :: :ok | {:error, any()}
  def save_state(state) do
    case bucket_name()
         |> ExAws.S3.put_object("manager_state.json", Jason.encode!(state))
         |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to update manager_state.json #{inspect(reason)}")

        {:error, reason}
    end

    :ok
  end

  @spec upload_raw_image(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def upload_raw_image(id, file_path) do
    key = "raw_images/#{id}.jpg"

    # Use streaming upload for better memory efficiency with large files
    case file_path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket_name(), key,
           content_type: "image/jpeg",
           acl: :private2
         )
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compress and upload an image to the 'compressed_images' S3 folder.
  Uses Mogrify for JPEG compression and resizing.
  """
  @spec upload_compressed_image(String.t(), String.t()) :: :ok | {:error, any()}
  def upload_compressed_image(id, file_path) do
    # Use Mogrify to compress and resize the image
    tmp_path = "/tmp/compressed_#{id}.jpg"
    try do
      Mogrify.open(file_path)
      |> Mogrify.format("jpg")
      |> Mogrify.quality(80)
      |> Mogrify.resize_to_limit("1600x1600")
      |> Mogrify.save(path: tmp_path)

      key = "compressed_images/#{id}.jpg"
      case tmp_path
           |> ExAws.S3.Upload.stream_file()
           |> ExAws.S3.upload(bucket_name(), key,
             content_type: "image/jpeg",
             acl: :private
           )
           |> ExAws.request() do
        {:ok, _response} ->
          :ok
        {:error, reason} ->
          {:error, reason}
      end
    after
      File.rm(tmp_path)
    end
  end

  @doc """
  folder can be "raw_images", "headshots", or "papers"
  """
  @spec presigned_url(String.t(), String.t(), integer()) :: String.t()
  def presigned_url(folder, id, expires_in \\ 600) do
    key = "#{folder}/#{id}.jpg"

    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3),
        :get,
        bucket_name(),
        key,
        expires_in: expires_in
      )

    url
  end

  def bucket_name do
    "headshot-plus-text-extractor"
  end

  @doc """
  Upload a template file to the 'templates' S3 folder.
  Accepts a template id (or name) and a file path.
  Returns :ok or {:error, reason}.
  """
  @spec upload_template(String.t()) :: :ok | {:error, any()}
  def upload_template(file_path) do
    key = "template.pptx"
    case file_path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket_name(), key,
           content_type: "application/octet-stream",
           acl: :private
         )
         |> ExAws.request() do
      {:ok, _response} ->
        :ok
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a template file exists in S3.
  """
  @spec template_exists?() :: boolean()
  def template_exists? do
    key = "template.pptx"
    case bucket_name()
         |> ExAws.S3.head_object(key)
         |> ExAws.request() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get a presigned URL for downloading the template file.
  """
  @spec template_presigned_url(integer()) :: String.t()
  def template_presigned_url(expires_in \\ 600) do
    key = "template.pptx"
    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3),
        :get,
        bucket_name(),
        key,
        expires_in: expires_in
      )
    url
  end
end
