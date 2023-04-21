defmodule PhilomenaWeb.Image.TagChangeController do
  use PhilomenaWeb, :controller

  alias Philomena.Images.Image
  alias Philomena.TagChanges
  alias Philomena.Repo
  import Ecto.Query

  plug PhilomenaWeb.CanaryMapPlug, index: :show
  plug :load_and_authorize_resource, model: Image, id_name: "image_id", persisted: true

  def index(conn, _params) do
    image = conn.assigns.image

    batches =
      TagChanges.tag_change_batches_image(image, show_uncommitted?(conn))
      |> preload([
        :user,
        added_tag_changes: :tag,
        removed_tag_changes: :tag,
        image: [:user, tags: :aliases]
      ])
      |> Repo.paginate(conn.assigns.scrivener)

    render(conn, "index.html",
      title: "Tag Changes on Image #{image.id}",
      image: image,
      batches: batches,
      layout_class: "layout--wide"
    )
  end

  defp show_uncommitted?(conn) do
    !Canada.Can.can?(conn.assigns.current_user, :revert, Philomena.TagChanges.TagChange)
  end
end
