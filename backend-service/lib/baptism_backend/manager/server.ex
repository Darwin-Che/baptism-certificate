defmodule BaptismBackend.Manager.Server do
  @moduledoc """
  """

  use GenServer

  alias BaptismBackend.Extractor
  alias BaptismBackend.Uploader
  alias BaptismBackend.S3Storage
  alias BaptismBackend.Manager.State
  alias BaptismBackend.Struct.Profile

  require Logger

  # Public API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def open_session do
    GenServer.call(__MODULE__, :open_session)
  end

  def list_profiles do
    GenServer.call(__MODULE__, :list_profiles)
  end

  def get_profile(id) do
    GenServer.call(__MODULE__, {:get_profile, id})
  end


  def create_profile(file_path) do
    GenServer.call(__MODULE__, {:create_profile, file_path})
    :ok
  end

  def delete_profile(id) do
    GenServer.call(__MODULE__, {:delete_profile, id})
  end

  def extract_profiles(profile_ids) do
    GenServer.cast(__MODULE__, {:extract_profiles, profile_ids})
    :ok
  end

  def update_profile(id, attrs) do
    GenServer.call(__MODULE__, {:update_profile, id, attrs})
  end

  def generate_certificate(profile_ids) do
    GenServer.cast(__MODULE__, {:generate_certificate, profile_ids})
    :ok
  end

  def mark_reviewed(profile_ids) do
    GenServer.call(__MODULE__, {:mark_reviewed, profile_ids})
  end

  def unmark_reviewed(profile_ids) do
    GenServer.call(__MODULE__, {:unmark_reviewed, profile_ids})
  end

  def get_inference_url do
    GenServer.call(__MODULE__, :get_inference_url)
  end

  def set_inference_url(url) do
    GenServer.call(__MODULE__, {:set_inference_url, url})
  end

  def get_certificate_config do
    GenServer.call(__MODULE__, :get_certificate_config)
  end

  def set_certificate_config(config) do
    GenServer.call(__MODULE__, {:set_certificate_config, config})
  end

  # Genserver Internal Callbacks

  def init(_state) do
    {:ok, state} = S3Storage.fetch_state()
    {:ok, state}
  end

  def handle_call(:open_session, {from_pid, _ref}, %State{} = state) do
    new_state = %{state | session_pid: from_pid}
    {:reply, :ok, new_state}
  end

  def handle_call(:list_profiles, _from, %State{} = state) do
    {:reply, state.profiles, state}
  end

  def handle_call({:get_profile, id}, _from, %State{} = state) do
    profile = Enum.find(state.profiles, fn p -> p.id == id end)
    {:reply, profile, state}
  end

  def handle_call(:get_inference_url, _from, %State{} = state) do
    {:reply, state.inference_url, state}
  end

  def handle_call(:get_certificate_config, _from, %State{} = state) do
    {:reply, state.certificate_config, state}
  end

  def handle_call({:set_inference_url, url}, _from, %State{} = state) do
    new_state = %{state | inference_url: url}

    # Notify the session about the update
    notify_session(new_state, {:inference_url_updated, url})

    # Persist state to S3
    S3Storage.save_state(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:set_certificate_config, config}, _from, %State{} = state) do
    new_state = %{state | certificate_config: config}

    # Notify the session about the update
    notify_session(new_state, {:certificate_config_updated, config})

    # Persist state to S3
    S3Storage.save_state(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:create_profile, file_path}, _from, %State{} = state) do
    # Copy the uploaded file synchronously before LiveView cleans it up
    tmp_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    tmp_path = "/tmp/profile_upload_#{tmp_id}.jpg"

    case File.cp(file_path, tmp_path) do
      :ok ->
        # Get existing profile IDs to check for duplicates
        existing_ids = Enum.map(state.profiles, & &1.id)

        # Delegate to Uploader GenServer with copied file
        Uploader.upload(tmp_path, existing_ids, self())

        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to copy uploaded file: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_profile, id}, _from, %State{} = state) do
    profile = Enum.find(state.profiles, fn p -> p.id == id end)

    case profile do
      nil ->
        {:reply, {:error, :not_found}, state}

      _profile ->
        # Delete S3 files associated with this profile
        S3Storage.delete_profile_files(id)

        updated_profiles = Enum.reject(state.profiles, fn p -> p.id == id end)
        new_state = %{state | profiles: updated_profiles}

        # Notify the session about all profiles
        notify_session(new_state, {:profiles_updated, new_state.profiles})

        # Persist state to S3
        S3Storage.save_state(new_state)

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_profile, id, attrs}, _from, %State{} = state) do
    Logger.info("Updating profile #{id} with attrs #{inspect(attrs)}")
    profile = Enum.find(state.profiles, fn p -> p.id == id end)

    case profile do
      nil ->
        Logger.error("Update profile failed: profile #{id} not found")
        {:reply, {:error, :not_found}, state}

      profile ->
        updated_profile = Profile.merge(profile, Map.new(attrs))

        updated_profiles =
          Enum.map(state.profiles, fn p ->
            if p.id == id, do: updated_profile, else: p
          end)

        new_state = %{state | profiles: updated_profiles}

        # Notify the session about the updated profile
        notify_session(new_state, {:profile_updated, updated_profile})

        # Persist state to S3
        S3Storage.save_state(new_state)

        {:reply, {:ok, updated_profile}, new_state}
    end
  end

  def handle_cast({:generate_certificate, profile_ids}, %State{} = state) do
    Enum.each(state.profiles, fn %Profile{} = profile ->
      if profile.id in profile_ids do
        # Send to Certificate GenServer which will handle rate limiting
        BaptismBackend.Certificate.generate_certificate(profile, state.certificate_config, self())
      end
    end)
    {:noreply, state}
  end

  def handle_call({:mark_reviewed, profile_ids}, _from, %State{} = state) do
    updated_profiles =
      Enum.map(state.profiles, fn %Profile{} = profile ->
        if profile.id in profile_ids && profile.status == :generated do
          %{profile | status: :reviewed}
        else
          profile
        end
      end)

    new_state = %{state | profiles: updated_profiles}

    # Notify the session about all profiles
    notify_session(new_state, {:profiles_updated, new_state.profiles})

    # Persist state to S3
    S3Storage.save_state(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:unmark_reviewed, profile_ids}, _from, %State{} = state) do
    updated_profiles =
      Enum.map(state.profiles, fn %Profile{} = profile ->
        if profile.id in profile_ids && profile.status == :reviewed do
          %{profile | status: :generated}
        else
          profile
        end
      end)

    new_state = %{state | profiles: updated_profiles}

    # Notify the session about all profiles
    notify_session(new_state, {:profiles_updated, new_state.profiles})

    # Persist state to S3
    S3Storage.save_state(new_state)

    {:reply, :ok, new_state}
  end

  def handle_cast({:extract_profiles, profile_ids}, %State{} = state) do
    Enum.each(state.profiles, fn %Profile{} = profile ->
      if profile.id in profile_ids do
        # Send to Extractor which will handle rate limiting
        Extractor.extract(profile.id, state.inference_url, self())
      end
    end)
    {:noreply, state}
  end

  def handle_info({:upload_complete, _id, profile}, %State{} = state) do
    new_state = %{state | profiles: [profile | state.profiles]}
    notify_session(new_state, {:profiles_updated, new_state.profiles})
    S3Storage.save_state(new_state)
    {:noreply, new_state}
  end

  def handle_info({:upload_error, id, reason}, %State{} = state) do
    Logger.error("Upload failed for profile #{inspect(id)}: #{inspect(reason)}")
    notify_session(state, {:upload_error, id, reason})
    {:noreply, state}
  end

  def handle_info({:extraction_result, profile_id, {:ok, resp}}, state) do
    Logger.info("Extraction succeeded for profile #{profile_id}")
    updated_profiles = Enum.map(state.profiles, fn profile ->
      if profile.id == profile_id do
        updated = Profile.apply_extraction_result(profile, resp)
        %{updated | status: :extracted}
      else
        profile
      end
    end)
    new_state = %{state | profiles: updated_profiles}
    notify_session(new_state, {:profiles_updated, new_state.profiles})
    S3Storage.save_state(new_state)
    {:noreply, new_state}
  end

  def handle_info({:extraction_result, profile_id, {:error, reason}}, state) do
    Logger.error("Extraction failed for profile #{profile_id}: #{inspect(reason)}")
    notify_session(state, {:extract_error, profile_id, reason})
    {:noreply, state}
  end

  def handle_info({:certificate_result, profile_id, :ok}, state) do
    Logger.info("Certificate generation succeeded for profile #{profile_id}")
    updated_profiles = Enum.map(state.profiles, fn profile ->
      if profile.id == profile_id do
        %{profile | status: :generated}
      else
        profile
      end
    end)
    new_state = %{state | profiles: updated_profiles}
    notify_session(new_state, {:profiles_updated, new_state.profiles})
    S3Storage.save_state(new_state)
    {:noreply, new_state}
  end

  def handle_info({:certificate_result, profile_id, {:error, reason}}, state) do
    Logger.error("Certificate generation failed for profile #{profile_id}: #{inspect(reason)}")
    notify_session(state, {:certificate_error, profile_id, reason})
    {:noreply, state}
  end

  # Helper functions

  defp notify_session(%State{session_pid: nil}, _message), do: :ok

  defp notify_session(%State{session_pid: pid}, message) when is_pid(pid) do
    send(pid, message)
    :ok
  end
end
