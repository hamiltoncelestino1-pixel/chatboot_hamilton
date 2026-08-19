json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: @item,
                                             overdue_tasks_counts: { @item.id => @item.tasks.pending.where('due_date < ?', Time.current).count }
