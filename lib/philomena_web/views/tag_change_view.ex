defmodule PhilomenaWeb.TagChangeView do
  use PhilomenaWeb, :view

  def staff?(batch),
    do:
      not is_nil(batch.user) and not Philomena.Attribution.anonymous?(batch) and
        batch.user.role != "user" and not batch.user.hide_default_role

  def user_column_class(batch) do
    case staff?(batch) do
      true -> "success"
      false -> nil
    end
  end

  def reverts_tag_changes?(conn),
    do: can?(conn, :revert, Philomena.TagChanges.TagChange)

  def state_class(batch) do
    case batch.state do
      "committed" -> "success"
      "uncommitted" -> "warning"
      _ -> "danger"
    end
  end

  def state_name(batch) do
    case batch.state do
      "committed" -> "Visible"
      "uncommitted" -> "Pending"
      "rejected" -> "Rejected"
    end
  end

  def can_reject?(batch) do
    batch.state != "rejected"
  end
end
