defmodule PhilomenaWeb.UserAttributionPlug do
  @moduledoc """
  This plug stores information about the current session for use in
  model attribution.

  ## Example

      plug PhilomenaWeb.UserAttributionPlug
  """

  alias Plug.Conn

  @doc false
  @spec init(any()) :: any()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn = Conn.fetch_cookies(conn)
    attributes =
      %{
        ip:          conn.remote_ip,
        fingerprint: conn.cookies["_ses"],
        referrer:    conn.assigns.referrer,
        user_agent:  user_agent(conn),
        user_id:     user_id(conn)
      }

    conn
    |> Conn.assign(:attributes, attributes)
  end

  defp user_agent(conn) do
    case Conn.get_req_header(conn, "user-agent") do
      [ua] -> ua
      _    -> nil
    end
  end

  defp user_id(conn) do
    user = Pow.Plug.current_user(conn)

    case user do
      %{id: id} -> id
      _         -> nil
    end
  end
end