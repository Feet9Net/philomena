defmodule Philomena.TagChanges.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tag_change_batches" do
    belongs_to :user, Philomena.Users.User
    belongs_to :image, Philomena.Images.Image

    has_many :added_tag_changes, Philomena.TagChanges.TagChange,
      foreign_key: :tag_change_batch_id,
      where: [added: true]

    has_many :removed_tag_changes, Philomena.TagChanges.TagChange,
      foreign_key: :tag_change_batch_id,
      where: [added: false]

    field :state, :string
    field :ip, EctoNetwork.INET
    field :fingerprint, :string

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [])
    |> validate_required([])
  end

  def reject_changeset(batch) do
    change(batch, state: "rejected")
  end
end
