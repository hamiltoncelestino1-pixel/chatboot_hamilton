class MergeDuplicatePipelineItems < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    PipelineItems::DuplicateMerger.duplicate_groups.each do |group|
      PipelineItems::DuplicateMerger.merge_group!(group[:pipeline_item_ids])
    end
  end

  def down
    # no-op: merging duplicate cards is not reversible
  end
end
