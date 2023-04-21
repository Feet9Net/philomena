defmodule Philomena.Repo.Migrations.CreateTagChangeBatch do
  use Ecto.Migration

  def change do
    create table(:tag_change_batches) do
      timestamps(inserted_at: :created_at, updated_at: false)
      add :image_id, references(:images, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :state, :string, null: false
      add :fingerprint, :string
      add :ip, :inet
    end

    create index(:tag_change_batches, [:image_id, "created_at desc"])
    create index(:tag_change_batches, [:user_id, "created_at desc"])
    create index(:tag_change_batches, [:fingerprint, "created_at desc"])
    create index(:tag_change_batches, ["ip inet_ops"], using: "gist")
    create index(:tag_change_batches, [:state, "created_at desc"], where: "state = 'unconfirmed'")

    alter table(:tag_changes) do
      add :tag_change_batch_id, references(:tag_change_batches, on_delete: :delete_all)
    end

    # may take a while
    create index(:tag_changes, [:tag_change_batch_id, :added])
  end
end
