defmodule BaptismBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BaptismBackendWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:baptism_backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BaptismBackend.PubSub},
      # Start the Extractor GenServer for rate-limited inference calls
      BaptismBackend.Extractor,
      # Start the Uploader GenServer for rate-limited image uploads
      BaptismBackend.Uploader,
      # Start the Manager GenServer
      BaptismBackend.Manager.Server,
      # Start to serve requests, typically the last entry
      BaptismBackendWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BaptismBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BaptismBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
