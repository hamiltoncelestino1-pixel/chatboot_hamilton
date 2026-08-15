class TaskDrop < BaseDrop
  def title
    @obj.try(:title)
  end

  def due_date
    I18n.l(@obj.due_date, format: '%d/%m/%Y %H:%M')
  end

  def contact_name
    @obj.try(:contact).name.try(:capitalize) || 'Customer'
  end
end
