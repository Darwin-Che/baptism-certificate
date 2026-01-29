defmodule BaptismBackendWeb.PageController do
  use BaptismBackendWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
