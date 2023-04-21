defimpl Philomena.Attribution, for: Philomena.TagChanges.TagChange do
  def object_identifier(tag_change) do
    to_string(tag_change.image_id || tag_change.id)
  end

  def best_user_identifier(tag_change) do
    to_string(tag_change.user_id || tag_change.fingerprint || tag_change.ip)
  end

  def anonymous?(tag_change) do
    tag_change.user_id == tag_change.image.user_id and !!tag_change.image.anonymous
  end
end

defimpl Philomena.Attribution, for: Philomena.TagChanges.Batch do
  def object_identifier(batch) do
    to_string(batch.image_id || batch.id)
  end

  def best_user_identifier(batch) do
    to_string(batch.user_id || batch.fingerprint || batch.ip)
  end

  def anonymous?(batch) do
    batch.user_id == batch.image.user_id and !!batch.image.anonymous
  end
end
