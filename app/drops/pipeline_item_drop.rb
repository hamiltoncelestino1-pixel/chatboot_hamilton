class PipelineItemDrop < BaseDrop
  def title
    @obj.try(:title)
  end

  def contact_name
    @obj.try(:contact).try(:name).try(:capitalize) || 'Customer'
  end

  def days_stale
    return 0 if @obj.stage_changed_at.blank?

    ((Time.current - @obj.stage_changed_at) / 1.day).to_i
  end
end
