defmodule PhilomenaWeb.TagChange.RevertController do
  use PhilomenaWeb, :controller

  alias Philomena.TagChanges.TagChange
  alias Philomena.TagChanges

  plug :verify_authorized
  plug PhilomenaWeb.UserAttributionPlug

  def create(conn, %{"batch_id" => batch_id}) do
    batch = TagChanges.get_batch!(batch_id)

    case TagChanges.revert_batch(batch) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Successfully reverted batch of tag changes.")
        |> redirect(external: conn.assigns.referrer)

      _error ->
        conn
        |> put_flash(:error, "Couldn't revert those tag changes!")
        |> redirect(external: conn.assigns.referrer)
    end
  end

  defp verify_authorized(conn, _params) do
    case Canada.Can.can?(conn.assigns.current_user, :revert, TagChange) do
      true -> conn
      _false -> PhilomenaWeb.NotAuthorizedPlug.call(conn)
    end
  end
end
