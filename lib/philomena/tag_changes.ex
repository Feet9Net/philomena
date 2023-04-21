defmodule Philomena.TagChanges do
  @moduledoc """
  The TagChanges context.
  """

  import Ecto.Query, warn: false
  alias Philomena.Repo

  alias Philomena.TagChangeRevertWorker
  alias Philomena.TagChanges.TagChange
  alias Philomena.Images.Tagging
  alias Philomena.Tags.Tag
  alias Philomena.{Images, Images.Image, Images.Tagging}
  alias Ecto.Multi

  # TODO: this is substantially similar to Images.batch_update/4.
  # Perhaps it should be extracted.
  def mass_revert(ids, attributes) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tag_change_attributes = Map.merge(attributes, %{created_at: now, updated_at: now})
    tag_attributes = %{name: "", slug: "", created_at: now, updated_at: now}

    tag_changes =
      TagChange
      |> join(:inner, [tc], _ in assoc(tc, :image))
      |> where([tc, i], tc.id in ^ids and i.hidden_from_users == false)
      |> order_by(desc: :created_at)
      |> Repo.all()
      |> Enum.reject(&is_nil(&1.tag_id))
      |> Enum.uniq_by(&{&1.image_id, &1.tag_id})

    {added, removed} = Enum.split_with(tag_changes, & &1.added)

    image_ids =
      tag_changes
      |> Enum.map(& &1.image_id)
      |> Enum.uniq()

    to_remove =
      added
      |> Enum.map(&{&1.image_id, &1.tag_id})
      |> Enum.reduce(where(Tagging, fragment("'t' = 'f'")), fn {image_id, tag_id}, q ->
        or_where(q, image_id: ^image_id, tag_id: ^tag_id)
      end)
      |> select([t], [t.image_id, t.tag_id])

    to_add = Enum.map(removed, &%{image_id: &1.image_id, tag_id: &1.tag_id})

    Repo.transaction(fn ->
      {_count, inserted} =
        Repo.insert_all(Tagging, to_add, on_conflict: :nothing, returning: [:image_id, :tag_id])

      {_count, deleted} = Repo.delete_all(to_remove)

      inserted = Enum.map(inserted, &[&1.image_id, &1.tag_id])

      added_changes =
        Enum.map(inserted, fn [image_id, tag_id] ->
          Map.merge(tag_change_attributes, %{image_id: image_id, tag_id: tag_id, added: true})
        end)

      removed_changes =
        Enum.map(deleted, fn [image_id, tag_id] ->
          Map.merge(tag_change_attributes, %{image_id: image_id, tag_id: tag_id, added: false})
        end)

      Repo.insert_all(TagChange, added_changes ++ removed_changes)

      # In order to merge into the existing tables here in one go, insert_all
      # is used with a query that is guaranteed to conflict on every row by
      # using the primary key.

      added_upserts =
        inserted
        |> Enum.group_by(fn [_image_id, tag_id] -> tag_id end)
        |> Enum.map(fn {tag_id, instances} ->
          Map.merge(tag_attributes, %{id: tag_id, images_count: length(instances)})
        end)

      removed_upserts =
        deleted
        |> Enum.group_by(fn [_image_id, tag_id] -> tag_id end)
        |> Enum.map(fn {tag_id, instances} ->
          Map.merge(tag_attributes, %{id: tag_id, images_count: -length(instances)})
        end)

      update_query = update(Tag, inc: [images_count: fragment("EXCLUDED.images_count")])

      upserts = added_upserts ++ removed_upserts

      Repo.insert_all(Tag, upserts, on_conflict: update_query, conflict_target: [:id])
    end)
    |> case do
      {:ok, _result} ->
        Images.reindex_images(image_ids)

        {:ok, tag_changes}

      error ->
        error
    end
  end

  def full_revert(%{user_id: _user_id, attributes: _attributes} = params),
    do: Exq.enqueue(Exq, "indexing", TagChangeRevertWorker, [params])

  def full_revert(%{ip: _ip, attributes: _attributes} = params),
    do: Exq.enqueue(Exq, "indexing", TagChangeRevertWorker, [params])

  def full_revert(%{fingerprint: _fingerprint, attributes: _attributes} = params),
    do: Exq.enqueue(Exq, "indexing", TagChangeRevertWorker, [params])

  @doc """
  Gets a single tag_change.

  Raises `Ecto.NoResultsError` if the Tag change does not exist.

  ## Examples

      iex> get_tag_change!(123)
      %TagChange{}

      iex> get_tag_change!(456)
      ** (Ecto.NoResultsError)

  """
  def get_tag_change!(id), do: Repo.get!(TagChange, id)

  @doc """
  Creates a tag_change.

  ## Examples

      iex> create_tag_change(%{field: value})
      {:ok, %TagChange{}}

      iex> create_tag_change(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_tag_change(attrs \\ %{}) do
    %TagChange{}
    |> TagChange.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag_change.

  ## Examples

      iex> update_tag_change(tag_change, %{field: new_value})
      {:ok, %TagChange{}}

      iex> update_tag_change(tag_change, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_tag_change(%TagChange{} = tag_change, attrs) do
    tag_change
    |> TagChange.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a TagChange.

  ## Examples

      iex> delete_tag_change(tag_change)
      {:ok, %TagChange{}}

      iex> delete_tag_change(tag_change)
      {:error, %Ecto.Changeset{}}

  """
  def delete_tag_change(%TagChange{} = tag_change) do
    Repo.delete(tag_change)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tag_change changes.

  ## Examples

      iex> change_tag_change(tag_change)
      %Ecto.Changeset{source: %TagChange{}}

  """
  def change_tag_change(%TagChange{} = tag_change) do
    TagChange.changeset(tag_change, %{})
  end

  alias Philomena.TagChanges.Batch

  def tag_change_batches_image(%Image{id: image_id}, committed_only?) do
    Batch
    |> where(image_id: ^image_id)
    |> maybe_filter_uncommitted(committed_only?)
    |> order_by(desc: :created_at)
  end

  def tag_change_batches_fingerprint(fingerprint, committed_only?) do
    Batch
    |> where(fingerprint: ^fingerprint)
    |> maybe_filter_uncommitted(committed_only?)
    |> order_by(desc: :created_at)
  end

  def tag_change_batches_ip(cidr, committed_only?) do
    {:ok, inet} = EctoNetwork.INET.cast(cidr)

    Batch
    |> where(fragment("ip >>= ?", ^inet))
    |> maybe_filter_uncommitted(committed_only?)
    |> order_by(desc: :created_at)
  end

  defp maybe_filter_uncommitted(query, true),
    do: where(query, state: "committed")

  defp maybe_filter_uncommitted(query, _), do: query

  def revert_batch(%Batch{state: "uncommitted"} = batch) do
    # If the batch is uncommitted, then it hasn't been applied and we can just mark it as rejected.
    batch
    |> Batch.reject_changeset()
    |> Repo.update()
  end

  def revert_batch(%Batch{} = batch) do
    # We need to reverse the changes from the batch on this image.
    batch_changeset = Batch.reject_changeset(batch)

    # Calculate taggings to add as the batch's removed tags.
    taggings_to_add =
      batch.removed_tag_changes
      |> Enum.map(&%{image_id: batch.image_id, tag_id: &1.tag_id})

    # Calculate taggings to remove as the batch's added tags.
    tag_ids_to_remove = Enum.map(batch.added_tag_changes, &(&1.tag_id))
    taggings_to_remove =
      Tagging
      |> where([tc], tc.image_id == ^batch.image_id)
      |> where([tc], tc.tag_id in ^tag_ids_to_remove)
      |> select([tc], tc.tag_id)

    # Get the image during the transaction, so we know whether to update the tag counters.
    image_query = where(Image, id: ^batch.image_id)

    # Perform the transaction, avoiding creating tag change entries.
    Multi.new()
    |> Multi.update(:batch, batch_changeset)
    |> Multi.one(:image, image_query)
    |> Multi.run(:add_tags, fn repo, %{image: %{hidden_from_users: hidden}} ->
      # Insert the new taggings, returning which tag_ids were actually added.
      {_count, taggings} =
        repo.insert_all(Tagging, taggings_to_add, on_conflict: :nothing, returning: [:tag_id])

      # Update the image count on the tags which were added.
      if not hidden do
        tag_ids = Enum.map(taggings, &(&1.tag_id))

        Tag
        |> where([t], t.id in ^tag_ids)
        |> repo.update_all(inc: [images_count: 1])
      end

      # We succeeded.
      {:ok, 0}
    end)
    |> Multi.run(:remove_tags, fn repo, %{image: %{hidden_from_users: hidden}} ->
      # Delete the existing tags, returning which tag_ids were actually removed.
      {_count, taggings} =
        repo.delete_all(taggings_to_remove)

      # Update the image count on the tags which were removed.
      if not hidden do

        tag_ids = Enum.map(taggings, &(&1.tag_id))

        Tag
        |> where([t], t.id in ^tag_ids)
        |> repo.update_all(inc: [images_count: -1])
      end

      # We succeeded.
      {:ok, 0}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{batch: batch}} ->
        {:ok, batch}

      error ->
        error
    end
  end

  @doc """
  Gets a single batch.

  Raises `Ecto.NoResultsError` if the Batch does not exist.

  ## Examples

      iex> get_batch!(123)
      %Batch{}

      iex> get_batch!(456)
      ** (Ecto.NoResultsError)

  """
  def get_batch!(id) do
    Batch
    |> preload([added_tag_changes: :tag, removed_tag_changes: :tag])
    |> Repo.get!(id)
  end

  @doc """
  Creates a batch.

  ## Examples

      iex> create_batch(%{field: value})
      {:ok, %Batch{}}

      iex> create_batch(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_batch(attrs \\ %{}) do
    %Batch{}
    |> Batch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a batch.

  ## Examples

      iex> update_batch(batch, %{field: new_value})
      {:ok, %Batch{}}

      iex> update_batch(batch, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_batch(%Batch{} = batch, attrs) do
    batch
    |> Batch.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a batch.

  ## Examples

      iex> delete_batch(batch)
      {:ok, %Batch{}}

      iex> delete_batch(batch)
      {:error, %Ecto.Changeset{}}

  """
  def delete_batch(%Batch{} = batch) do
    Repo.delete(batch)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking batch changes.

  ## Examples

      iex> change_batch(batch)
      %Ecto.Changeset{data: %Batch{}}

  """
  def change_batch(%Batch{} = batch, attrs \\ %{}) do
    Batch.changeset(batch, attrs)
  end
end
