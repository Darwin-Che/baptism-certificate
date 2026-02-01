defmodule BaptismBackend.Uploader do
  @moduledoc """
  GenServer that handles profile image uploads with rate limiting.
  Ensures at most N concurrent uploads to prevent OOM issues.
  """
  use GenServer

  alias BaptismBackend.S3Storage
  alias BaptismBackend.Struct.Profile

  require Logger

  @max_concurrent_uploads 3

  defmodule State do
    defstruct queue: :queue.new(),
              active: MapSet.new()
  end

  # Public API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @doc """
  Queue a file upload. Returns immediately.
  Sends {:upload_complete, id, profile} or {:upload_error, id, reason} to caller_pid when done.
  """
  def upload(file_path, existing_profile_ids, caller_pid) do
    GenServer.cast(__MODULE__, {:upload, file_path, existing_profile_ids, caller_pid})
  end

  # GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:upload, tmp_path, existing_profile_ids, caller_pid}, state) do
    # File is already copied by Manager.Server, just calculate ID and queue
    try do
      # Calculate ID using streaming hash to avoid loading entire file into memory
      id = calculate_file_hash(tmp_path)

      # Check if ID already exists, if so generate a random one
      id =
        if id in existing_profile_ids do
          random_suffix =
            :crypto.strong_rand_bytes(4)
            |> Base.encode16(case: :lower)
            |> String.slice(0, 4)

          "dup_#{random_suffix}_#{id}"
        else
          id
        end

      # Add to queue
      new_queue = :queue.in({id, tmp_path, caller_pid}, state.queue)
      new_state = %{state | queue: new_queue}

      # Process queue
      new_state = process_queue(new_state)

      {:noreply, new_state}
    rescue
      error ->
        Logger.error("Failed to prepare upload: #{inspect(error)}")
        # Clean up the tmp file on error
        File.rm(tmp_path)
        send(caller_pid, {:upload_error, nil, error})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:upload_complete, id}, state) do
    # Remove from active set
    new_active = MapSet.delete(state.active, id)
    new_state = %{state | active: new_active}

    # Process next item in queue
    new_state = process_queue(new_state)

    {:noreply, new_state}
  end

  # Private Functions

  defp process_queue(state) do
    active_count = MapSet.size(state.active)

    if active_count >= @max_concurrent_uploads or :queue.is_empty(state.queue) do
      state
    else
      {{:value, {id, tmp_path, caller_pid}}, new_queue} = :queue.out(state.queue)

      uploader_pid = self()

      Task.start(fn ->
        try do
          S3Storage.upload_raw_image(id, tmp_path)
          S3Storage.upload_compressed_image(id, tmp_path)
          File.rm(tmp_path)

          Logger.info("Uploaded images for profile #{id} to S3")

          # Create a new profile struct
          profile = %Profile{
            id: id,
            status: :uploaded
          }

          send(caller_pid, {:upload_complete, id, profile})
          send(uploader_pid, {:upload_complete, id})
        rescue
          error ->
            Logger.error("Upload failed for profile #{id}: #{inspect(error)}")
            File.rm(tmp_path)
            send(caller_pid, {:upload_error, id, error})
            send(uploader_pid, {:upload_complete, id})
        end
      end)

      new_active = MapSet.put(state.active, id)
      new_state = %{state | queue: new_queue, active: new_active}

      # Recursively process queue to fill up to max concurrent
      process_queue(new_state)
    end
  end

  # Stream-based file hashing to avoid loading entire file into memory
  defp calculate_file_hash(file_path) do
    file_path
    |> File.stream!([], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end
end
