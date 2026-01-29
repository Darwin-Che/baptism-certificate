defmodule BaptismBackend.Extractor do
  @moduledoc """
  Wrapper for calling the inference server's /extract endpoint.
  """

  require Logger

  @default_url "http://localhost:8000/extract"

  @doc """
  Calls the inference server's /extract endpoint with the given payload.
  The payload should be a map with the required fields for extraction.
  Optionally, you can override the inference server URL.
  """
  @spec extract(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def extract(id, url \\ @default_url) do
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
