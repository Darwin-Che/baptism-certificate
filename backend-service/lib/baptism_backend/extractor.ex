defmodule BaptismBackend.Extractor do
  @moduledoc """
  Wrapper for calling the inference server's /extract endpoint with rate limiting.
  Limits concurrent extractions to 2 to avoid overwhelming the inference server.
  """

  use GenServer
  require Logger

  @default_url "http://localhost:8000/extract"
  @max_concurrent 2

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Calls the inference server's /extract endpoint with the given payload.
  This function queues the request and processes it with rate limiting.
  Returns immediately - the caller should handle the result via message passing.
  """
  @spec extract(String.t(), String.t(), pid()) :: :ok
  def extract(id, url \\ @default_url, reply_to) do
    GenServer.cast(__MODULE__, {:extract, id, url, reply_to})
  end

  # Server Callbacks

  @impl true
  def init(_) do
    state = %{
      queue: :queue.new(),
      active: MapSet.new()
    }
    {:ok, state}
  end

  @impl true
  def handle_cast({:extract, id, url, reply_to}, state) do
    # Add to queue
    new_queue = :queue.in({id, url, reply_to}, state.queue)
    new_state = %{state | queue: new_queue}

    # Try to process queue
    new_state = process_queue(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:extraction_complete, id}, state) do
    # Remove from active set
    new_active = MapSet.delete(state.active, id)
    new_state = %{state | active: new_active}

    # Try to process next in queue
    new_state = process_queue(new_state)
    {:noreply, new_state}
  end

  # Private Helpers

  defp process_queue(state) do
    active_count = MapSet.size(state.active)

    if active_count < @max_concurrent and !:queue.is_empty(state.queue) do
      # Get next item from queue
      {{:value, {id, url, reply_to}}, new_queue} = :queue.out(state.queue)

      # Start extraction task
      parent = self()
      Task.start(fn ->
        result = do_extract(id, url)
        send(reply_to, {:extraction_result, id, result})
        send(parent, {:extraction_complete, id})
      end)

      Logger.info("Started extraction for #{id} (#{active_count + 1}/#{@max_concurrent} active)")

      # Update state and recursively process
      new_state = %{state | queue: new_queue, active: MapSet.put(state.active, id)}
      process_queue(new_state)
    else
      state
    end
  end

  defp do_extract(id, url) do
    Logger.info("Extractor: Sending extraction request for ID #{id} to #{url}")

    headers = [
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{filename: "#{id}.jpg"})

    case HTTPoison.post("#{url}/extract", body, headers, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, data} ->
            Logger.info("Extractor: result for ID #{id} \n #{inspect(data)}")
            {:ok, data}

          error ->
            error
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.error("Extractor: Unexpected status #{code}: #{resp_body}")
        {:error, {:http_error, code, resp_body}}

      {:error, reason} ->
        Logger.error("Extractor: HTTP error #{inspect(reason)}")
        {:error, reason}
    end
  end
end
