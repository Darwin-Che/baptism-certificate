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
    {:ok, _profile} = Profiles.generate_certificate(id)

    {:noreply,
     socket
     |> put_flash(:info, "Certificate generated successfully")
     |> assign(:profiles, Profiles.list_profiles())
     |> assign(:selected_profile, Profiles.get_profile(id))}
  end

  @impl true
  def handle_event("mark_reviewed", %{"id" => id}, socket) do
    {:ok, _profile} = Profiles.mark_reviewed(id)

    {:noreply,
     socket
     |> put_flash(:info, "Profile marked as reviewed")
     |> assign(:profiles, Profiles.list_profiles())
     |> assign(:selected_profile, Profiles.get_profile(id))}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    Logger.info(
      "Validate event - Upload entries: #{inspect(socket.assigns.uploads.images.entries)}"
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_template", _params, socket) do
    Logger.info(
      "Validate template event - Upload entries: #{inspect(socket.assigns.uploads.template_file.entries)}"
    )

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
      case BaptismBackend.S3Storage.upload_template(path) do
        :ok -> {:ok, :success}
        {:error, reason} -> {:postpone, reason}
      end
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
end
