defmodule BaptismBackend.S3Storage do
  @moduledoc """
  Module for handling S3 storage operations.
  """
  alias BaptismBackend.Manager.State

  require Logger

  def upload_file(s3_key, local_path) do
    case local_path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket_name(), s3_key,
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
  Upload a PNG preview file with inline content disposition for browser viewing.
  """
  def upload_pdf_preview(s3_key, local_path) do
    case local_path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket_name(), s3_key,
           content_type: "image/png",
           content_disposition: "inline",
           acl: :private
         )
         |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

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
  folder can be "raw_images", "headshots[_rembg]", or "papers"
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

  def presigned_url_png(folder, id, expires_in \\ 600) do
    key = "#{folder}/#{id}.png"

    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3),
        :get,
        bucket_name(),
        key,
        expires_in: expires_in,
        query_params: [{"response-content-disposition", "inline"}]
      )

    url
  end

  @doc """
  Get a presigned URL for downloading a certificate PPTX file.
  """
  @spec certificate_pptx_presigned_url(String.t(), String.t() | nil, integer()) :: String.t()
  def certificate_pptx_presigned_url(id, filename \\ nil, expires_in \\ 600) do
    key = "certificates/#{id}.pptx"
    download_filename = filename || "certificate_#{id}.pptx"

    {:ok, url} =
      ExAws.S3.presigned_url(
        ExAws.Config.new(:s3),
        :get,
        bucket_name(),
        key,
        query_params: [{"response-content-disposition", "attachment; filename=\"#{download_filename}\""}],
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

  @doc """
  Download a template file from S3 to a local path.
  """
  @spec download_template(String.t()) :: :ok | {:error, any()}
  def download_template(local_path) do
    key = "template.pptx"

    case bucket_name()
         |> ExAws.S3.get_object(key)
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write(local_path, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Download a headshot image from S3 to a local path.
  """
  @spec download_headshot(String.t(), String.t()) :: :ok | {:error, any()}
  def download_headshot(id, local_path) do
    key = "headshots_rembg/#{id}.jpg"

    case bucket_name()
         |> ExAws.S3.get_object(key)
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write(local_path, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Download a certificate PPTX file from S3 and return the binary content.
  """
  @spec download_certificate(String.t()) :: {:ok, binary()} | {:error, any()}
  def download_certificate(id) do
    key = "certificates/#{id}.pptx"

    case bucket_name()
         |> ExAws.S3.get_object(key)
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete all S3 files associated with a profile ID.
  Removes files from: raw_images, compressed_images, headshots, papers, certificates, certificate_previews
  """
  @spec delete_profile_files(String.t()) :: :ok
  def delete_profile_files(id) do
    folders = [
      {"raw_images", ".jpg"},
      {"compressed_images", ".jpg"},
      {"headshots", ".jpg"},
      {"headshots_rembg", ".jpg"},
      {"papers", ".jpg"},
      {"certificates", ".pptx"},
      {"certificate_previews", ".png"}
    ]

    Enum.each(folders, fn {folder, ext} ->
      key = "#{folder}/#{id}#{ext}"

      case bucket_name()
           |> ExAws.S3.delete_object(key)
           |> ExAws.request() do
        {:ok, _} ->
          Logger.info("Deleted S3 file: #{key}")
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete S3 file #{key}: #{inspect(reason)}")
          :ok  # Continue even if delete fails (file might not exist)
      end
    end)

    :ok
  end
end
