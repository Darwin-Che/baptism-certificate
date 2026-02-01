defmodule BaptismBackendWeb.ProfileLive.Index do
  use BaptismBackendWeb, :live_view

  alias BaptismBackend.Manager.Server, as: Manager
  alias BaptismBackend.Profiles

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Open session with the Manager GenServer
    :ok = Manager.open_session()

    {:ok,
     socket
     |> assign(:profiles, Manager.list_profiles())
     |> assign(:selected_profile, nil)
     |> assign(:uploaded_files, [])
     |> assign(:show_settings_dialog, false)
     |> assign(:show_flash_messages, false)
     |> assign(:inference_url, Manager.get_inference_url() || "")
     |> assign(:certificate_config, Manager.get_certificate_config() || %{})
     |> assign(:template_exists, BaptismBackend.S3Storage.template_exists?())
     |> allow_upload(:images,
       accept: ~w(.jpg .jpeg),
       max_entries: 16,
       auto_upload: false,
       chunk_size: 64_000,
       max_file_size: 10_000_000
     )
     |> allow_upload(:template_file,
       accept: ~w(.pptx),
       max_entries: 1,
       auto_upload: false,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"id" => id}) do
    profile = Manager.get_profile(id)

    original_image_url =
      if profile, do: BaptismBackend.S3Storage.presigned_url("raw_images", profile.id), else: nil

    compressed_original_image_url =
      if profile, do: BaptismBackend.S3Storage.presigned_url("compressed_images", profile.id), else: nil

    headshot_url =
      if profile, do: BaptismBackend.S3Storage.presigned_url("headshots", profile.id), else: nil

    paper_url =
      if profile, do: BaptismBackend.S3Storage.presigned_url("papers", profile.id), else: nil

    certificate_url =
      if profile,
        do: BaptismBackend.S3Storage.presigned_url("certificates", profile.id),
        else: nil

    socket
    |> assign(:page_title, "Profile Details")
    |> assign(:selected_profile, profile)
    |> assign(:compressed_original_image_url, compressed_original_image_url)
    |> assign(:original_image_url, original_image_url)
    |> assign(:headshot_url, headshot_url)
    |> assign(:paper_url, paper_url)
    |> assign(:certificate_url, certificate_url)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Profiles")
    |> assign(:selected_profile, nil)
  end

  @impl true
  def handle_event("toggle_flash", _params, socket) do
    show = Map.get(socket.assigns, :show_flash_messages, false)
    {:noreply, assign(socket, :show_flash_messages, !show)}
  end

  @impl true
  def handle_event("select_profile", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/profiles?id=#{id}")}
  end

  @impl true
  def handle_event("delete_profile", %{"id" => id}, socket) do
    :ok = Manager.delete_profile(id)

    # Clear selected profile if it was the deleted one
    selected_profile =
      if socket.assigns.selected_profile && socket.assigns.selected_profile.id == id do
        nil
      else
        socket.assigns.selected_profile
      end

    {:noreply,
     socket
     |> put_flash(:info, "Profile deleted successfully")
     |> assign(:profiles, Manager.list_profiles())
     |> assign(:selected_profile, selected_profile)}
  end

  @impl true
  def handle_event("generate_certificate", %{"id" => id}, socket) do
    :ok = Manager.generate_certificate([id])

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_reviewed", %{"id" => id}, socket) do
    :ok = Manager.mark_reviewed([id])
    {:noreply, socket}
  end

  @impl true
  def handle_event("unmark_reviewed", %{"id" => id}, socket) do
    :ok = Manager.unmark_reviewed([id])
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_all", _params, socket) do
    profiles = Manager.list_profiles()
    profile_ids =
      profiles
      |> Enum.filter(fn p -> p.status == :extracted end)
      |> Enum.map(& &1.id)

    # Generate certificates for all extracted profiles (async)
    Manager.generate_certificate(profile_ids)

    {:noreply,
     put_flash(
       socket,
       :info,
       "Generating certificates for #{length(profile_ids)} profiles (processing in background)"
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_template", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    Logger.info(
      "Save event triggered! Upload entries: #{length(socket.assigns.uploads.images.entries)}"
    )

    consume_uploaded_entries(socket, :images, fn %{path: path}, _entry ->
      # Upload to S3 and create profile via Manager
      Logger.info("Index: Creating profile for uploaded file #{path}")
      Manager.create_profile(path)
      {:ok, nil}
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings_dialog, true)}
  end

  @impl true
  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings_dialog, false)}
  end

  @impl true
  def handle_event("save_inference_url", %{"value" => url}, socket) do
    # Only save if the URL has actually changed
    if url != socket.assigns.inference_url do
      :ok = Manager.set_inference_url(url)

      {:noreply,
       socket
       |> assign(:inference_url, url)
       |> put_flash(:info, "Inference URL updated successfully")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_certificate_config", params, socket) do
    config = %{
      "headshot" => Map.get(params, "headshot", ""),
      "name" => Map.get(params, "name", ""),
      "birthday" => Map.get(params, "birthday", ""),
      "baptism_day" => Map.get(params, "baptism_day", ""),
      "baptism_month" => Map.get(params, "baptism_month", ""),
      "baptism_year" => Map.get(params, "baptism_year", ""),
      "sign_date" => Map.get(params, "sign_date", "")
    }

    :ok = Manager.set_certificate_config(config)

    {:noreply,
     socket
     |> assign(:certificate_config, config)
     |> put_flash(:info, "Certificate configuration saved")}
  end

  @impl true
  def handle_event("extract_profile", %{"id" => id}, socket) do
    # Extract only the selected profile (async)
    Manager.extract_profiles([id])

    {:noreply,
     put_flash(socket, :info, "Sent profile #{id} for extraction (processing in background)")}
  end

  @impl true
  def handle_event("extract_all", _params, socket) do
    profiles = Manager.list_profiles()
    profile_ids =
      profiles
      |> Enum.filter(fn p -> p.status == :uploaded end)
      |> Enum.map(& &1.id)

    # Send to inference server (async)
    Manager.extract_profiles(profile_ids)

    {:noreply,
     put_flash(
       socket,
       :info,
       "Sent #{length(profile_ids)} profiles for extraction (processing in background)"
     )}
  end

  @impl true
  def handle_event("save_profile_info", %{"profile" => attrs}, socket) do
    # Persist changes to server state
    id = socket.assigns.selected_profile.id
    {:ok, _profile} = Manager.update_profile(id, attrs)

    # Refresh selected_profile and profiles
    profiles = Manager.list_profiles()
    selected_profile = Enum.find(profiles, fn p -> p.id == id end)

    {:noreply,
     socket
     |> put_flash(:info, "Profile updated successfully!")
     |> assign(:profiles, profiles)
     |> assign(:selected_profile, selected_profile)}
  end

  @impl true
  def handle_event("upload_template", _params, socket) do
    Logger.info("upload_template event triggered, entries: #{inspect(socket.assigns.uploads.template_file.entries)}")

    uploaded_files = consume_uploaded_entries(socket, :template_file, fn %{path: path}, _entry ->
      Logger.info("Uploading template file from #{path}")
      result = case BaptismBackend.S3Storage.upload_template(path) do
        :ok -> {:ok, :success}
        {:error, reason} -> {:postpone, reason}
      end
      Logger.info("Upload result: #{inspect(result)}")
      result
    end)

    if uploaded_files != [] do
      {:noreply,
       socket
       |> put_flash(:info, "Template uploaded successfully")
       |> assign(:template_exists, true)
       |> assign(:show_settings_dialog, false)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Failed to upload template")}
    end
  end

  @impl true
  def handle_event("download_template", _params, socket) do
    if socket.assigns.template_exists do
      url = BaptismBackend.S3Storage.template_presigned_url()
      {:noreply, redirect(socket, external: url)}
    else
      {:noreply, put_flash(socket, :error, "No template available to download")}
    end
  end

  def handle_event("download_combined_reviewed", _params, socket) do
    reviewed_profiles =
      socket.assigns.profiles
      |> Enum.filter(fn p -> p.status == :reviewed end)

    Logger.info("Preparing to download #{length(reviewed_profiles)} reviewed certificates as combined PPTX")

    if Enum.empty?(reviewed_profiles) do
      {:noreply, put_flash(socket, :error, "No reviewed certificates available to download")}
    else
      # Get profile IDs
      profile_ids = Enum.map(reviewed_profiles, & &1.id)

      # Create combined PPTX file using Certificate module
      case BaptismBackend.Certificate.combine_certificates(profile_ids) do
        {:ok, pptx_binary} ->
          # Send the combined PPTX file as a download
          timestamp = DateTime.utc_now() |> DateTime.to_unix()
          filename = "baptism_certificates_#{timestamp}.pptx"

          {:noreply,
           socket
           |> push_event("download_file", %{
             data: Base.encode64(pptx_binary),
             filename: filename,
             mime_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
           })}

        {:error, reason} ->
          Logger.error("Failed to create combined PPTX: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to create combined PPTX: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("download_zip_reviewed", _params, socket) do
    reviewed_profiles =
      socket.assigns.profiles
      |> Enum.filter(fn p -> p.status == :reviewed end)

    Logger.info("Preparing to download #{length(reviewed_profiles)} reviewed certificates as zip")

    if Enum.empty?(reviewed_profiles) do
      {:noreply, put_flash(socket, :error, "No reviewed certificates available to download")}
    else
      # Create zip file in memory
      case create_certificates_zip(reviewed_profiles) do
        {:ok, zip_binary} ->
          # Send the zip file as a download
          timestamp = DateTime.utc_now() |> DateTime.to_unix()
          filename = "baptism_certificates_#{timestamp}.zip"

          {:noreply,
           socket
           |> push_event("download_file", %{
             data: Base.encode64(zip_binary),
             filename: filename,
             mime_type: "application/zip"
           })}

        {:error, reason} ->
          Logger.error("Failed to create zip file: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to create zip file: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("download_zip_reviewed", _params, socket) do
    reviewed_profiles =
      socket.assigns.profiles
      |> Enum.filter(fn p -> p.status == :reviewed end)

    Logger.info("Preparing to download #{length(reviewed_profiles)} reviewed certificates as zip")

    if Enum.empty?(reviewed_profiles) do
      {:noreply, put_flash(socket, :error, "No reviewed certificates available to download")}
    else
      # Create zip file in memory
      case create_certificates_zip(reviewed_profiles) do
        {:ok, zip_binary} ->
          # Send the zip file as a download
          timestamp = DateTime.utc_now() |> DateTime.to_unix()
          filename = "baptism_certificates_#{timestamp}.zip"

          {:noreply,
           socket
           |> push_event("download_file", %{
             data: Base.encode64(zip_binary),
             filename: filename,
             mime_type: "application/zip"
           })}

        {:error, reason} ->
          Logger.error("Failed to create zip file: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to create zip file: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_info({:profiles_updated, profiles}, socket) do
    # Refresh selected_profile if present
    selected_profile =
      case socket.assigns.selected_profile do
        nil -> nil
        %{id: id} -> Enum.find(profiles, fn p -> p.id == id end)
      end

    {:noreply,
     socket
     |> assign(:profiles, profiles)
     |> assign(:selected_profile, selected_profile)}
  end

  @impl true
  def handle_info({:extract_error, id, reason}, socket) do
    msg = "Extraction failed for profile #{id}: #{inspect(reason)}"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:upload_error, id, reason}, socket) do
    msg = if id, do: "Upload failed for profile #{id}: #{inspect(reason)}", else: "Upload failed: #{inspect(reason)}"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:certificate_error, id, reason}, socket) do
    msg = "Certificate generation failed for profile #{id}: #{inspect(reason)}"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:profile_updated, profile}, socket) do
    selected_profile =
      if socket.assigns.selected_profile && socket.assigns.selected_profile.id == profile.id do
        profile
      else
        socket.assigns.selected_profile
      end

    {:noreply,
     socket
     |> assign(:profiles, Manager.list_profiles())
     |> assign(:selected_profile, selected_profile)}
  end

  @impl true
  def handle_info({:inference_url_updated, url}, socket) do
    {:noreply, assign(socket, :inference_url, url)}
  end

  @impl true
  def handle_info({:certificate_config_updated, config}, socket) do
    {:noreply, assign(socket, :certificate_config, config)}
  end

  # Helper function to create a zip file of all reviewed certificates
  defp create_certificates_zip(reviewed_profiles) do
    files =
      reviewed_profiles
      |> Enum.map(fn profile ->
        case BaptismBackend.S3Storage.download_certificate(profile.id) do
          {:ok, content} ->
            # Create filename from profile info
            name = String.replace(profile.name_pinyin || profile.id, " ", "")
            filename = "#{name}_#{profile.birthday}.pptx"
            {String.to_charlist(filename), content}

          {:error, _reason} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(files) do
      {:error, "No certificates could be downloaded"}
    else
      case :zip.create("memory.zip", files, [:memory]) do
        {:ok, {"memory.zip", zip_binary}} ->
          {:ok, zip_binary}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
