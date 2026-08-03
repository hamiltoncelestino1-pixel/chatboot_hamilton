require 'rails_helper'

RSpec.describe AutomationRules::ActionService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:rule) do
    create(:automation_rule, account: account,
                             actions: [
                               { action_name: 'send_webhook_event', action_params: ['https://example.com'] },
                               { action_name: 'send_message', action_params: { message: 'Hello' } }
                             ])
  end

  describe '#perform' do
    context 'when actions are defined in the rule' do
      it 'will call the actions' do
        expect(Messages::MessageBuilder).to receive(:new)
        expect(WebhookJob).to receive(:perform_later)
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with send_attachment action' do
      let(:message_builder) { double }

      before do
        allow(Messages::MessageBuilder).to receive(:new).and_return(message_builder)
        rule.actions.delete_if { |a| a['action_name'] == 'send_message' }
        rule.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        rule.save!
        rule.actions << { action_name: 'send_attachment', action_params: [rule.files.first.blob_id] }
      end

      it 'will send attachment' do
        expect(message_builder).to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end

      it 'will not send attachment is conversation is a tweet' do
        twitter_inbox = create(:inbox, channel: create(:channel_twitter_profile, account: account))
        conversation = create(:conversation, inbox: twitter_inbox, additional_attributes: { type: 'tweet' })
        expect(message_builder).not_to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with send_webhook_event action' do
      it 'will send webhook event' do
        expect(rule.actions.pluck('action_name')).to include('send_webhook_event')
        expect(WebhookJob).to receive(:perform_later)
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with send_message action' do
      let(:message_builder) { double }

      before do
        allow(Messages::MessageBuilder).to receive(:new).and_return(message_builder)
      end

      it 'will send message' do
        expect(rule.actions.pluck('action_name')).to include('send_message')
        expect(message_builder).to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end

      it 'will not send message if conversation is a tweet' do
        expect(rule.actions.pluck('action_name')).to include('send_message')
        twitter_inbox = create(:inbox, channel: create(:channel_twitter_profile, account: account))
        conversation = create(:conversation, inbox: twitter_inbox, additional_attributes: { type: 'tweet' })
        expect(message_builder).not_to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with send_email_to_team action' do
      let!(:team) { create(:team, account: account) }

      before do
        rule.actions << { action_name: 'send_email_to_team', action_params: [{ team_ids: [team.id], message: 'Hello' }] }
      end

      it 'will send email to team' do
        expect(TeamNotifications::AutomationNotificationMailer).to receive(:conversation_creation).with(conversation, team, 'Hello').and_call_original
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with remove assignment actions' do
      let!(:team) { create(:team, account: account) }

      before do
        conversation.update!(assignee: agent, team: team)
        rule.actions = [
          { action_name: 'remove_assigned_agent', action_params: [] },
          { action_name: 'remove_assigned_team', action_params: [] }
        ]
        rule.save!
      end

      it 'removes assignee and team from the conversation' do
        described_class.new(rule, account, conversation).perform

        expect(conversation.reload.assignee).to be_nil
        expect(conversation.team).to be_nil
      end
    end

    describe '#perform with send_email_transcript action' do
      before do
        allow(account).to receive(:email_transcript_enabled?).and_return(true)
        allow(account).to receive(:within_email_rate_limit?).and_return(true)
        allow(account).to receive(:increment_email_sent_count).and_return(true)
        rule.actions << { action_name: 'send_email_transcript', action_params: ['contact@example.com, agent@example.com,agent1@example.com'] }
        rule.save
      end

      it 'will send email to transcript to action params emails' do
        mailer = double
        allow(ConversationReplyMailer).to receive(:with).and_return(mailer)
        allow(mailer).to receive(:conversation_transcript).with(conversation, 'contact@example.com')
        allow(mailer).to receive(:conversation_transcript).with(conversation, 'agent@example.com')
        allow(mailer).to receive(:conversation_transcript).with(conversation, 'agent1@example.com')

        described_class.new(rule, account, conversation).perform
        expect(mailer).to have_received(:conversation_transcript).exactly(3).times
      end

      it 'will send email to transcript to contacts' do
        rule.actions = [{ action_name: 'send_email_transcript', action_params: ['{{contact.email}}'] }]
        rule.save

        mailer = double
        allow(ConversationReplyMailer).to receive(:with).and_return(mailer)
        allow(mailer).to receive(:conversation_transcript).with(conversation, conversation.contact.email)

        described_class.new(rule.reload, account, conversation).perform
        expect(mailer).to have_received(:conversation_transcript).exactly(1).times
      end
    end

    describe '#perform with add_label action' do
      before do
        rule.actions << { action_name: 'add_label', action_params: %w[bug feature] }
        rule.save
      end

      it 'will add labels to conversation' do
        described_class.new(rule, account, conversation).perform
        expect(conversation.reload.label_list).to include('bug', 'feature')
      end

      it 'will not duplicate existing labels' do
        conversation.add_labels(['bug'])
        described_class.new(rule, account, conversation).perform
        expect(conversation.reload.label_list.count('bug')).to eq(1)
        expect(conversation.reload.label_list).to include('feature')
      end
    end

    describe '#perform with remove_label action' do
      before do
        conversation.add_labels(%w[bug feature support])
        rule.actions << { action_name: 'remove_label', action_params: %w[bug feature] }
        rule.save
      end

      it 'will remove specified labels from conversation' do
        described_class.new(rule, account, conversation).perform
        expect(conversation.reload.label_list).not_to include('bug', 'feature')
        expect(conversation.reload.label_list).to include('support')
      end

      it 'will not fail if labels do not exist on conversation' do
        conversation.update_labels(['support']) # Remove bug and feature first
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
        expect(conversation.reload.label_list).to include('support')
      end
    end

    describe '#perform with add_private_note action' do
      let(:message_builder) { double }

      before do
        allow(Messages::MessageBuilder).to receive(:new).and_return(message_builder)
        rule.actions.delete_if { |a| a['action_name'] == 'send_message' }
        rule.actions << { action_name: 'add_private_note', action_params: ['Note'] }
      end

      it 'will add private note' do
        expect(message_builder).to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end

      it 'will not add note if conversation is a tweet' do
        twitter_inbox = create(:inbox, channel: create(:channel_twitter_profile, account: account))
        conversation = create(:conversation, inbox: twitter_inbox, additional_attributes: { type: 'tweet' })
        expect(message_builder).not_to receive(:perform)
        described_class.new(rule, account, conversation).perform
      end
    end

    describe '#perform with create_pipeline_item action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        create(:pipeline_member, pipeline: pipeline, user: agent)
        conversation.update!(assignee: agent)
        rule.actions << {
          action_name: 'create_pipeline_item',
          action_params: [{ pipeline_id: pipeline.id, pipeline_stage_id: stage.id, assignee_mode: 'conversation_assignee', title: 'From automation' }]
        }
        rule.save!
      end

      it 'creates a pipeline item for the conversation contact' do
        described_class.new(rule, account, conversation).perform

        item = PipelineItem.find_by(contact_id: conversation.contact_id, pipeline_id: pipeline.id)
        expect(item).to be_present
        expect(item.conversation_id).to eq(conversation.id)
        expect(item.assignee_id).to eq(agent.id)
        expect(item.title).to eq('From automation')
      end

      it 'logs via ChatwootExceptionTracker and keeps running other actions when the contact already has a card' do
        create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)
        rule.actions << { action_name: 'remove_assigned_agent', action_params: [] }
        rule.save!

        expect(ChatwootExceptionTracker).to receive(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account).and_call_original
        described_class.new(rule, account, conversation).perform

        expect(conversation.reload.assignee).to be_nil
      end
    end

    describe '#perform with move_pipeline_item_stage action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:start_stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
      let(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }

      before do
        rule.actions << { action_name: 'move_pipeline_item_stage', action_params: [{ pipeline_id: pipeline.id, target_stage_id: won_stage.id }] }
        rule.save!
      end

      it 'moves the existing card to the target stage' do
        item = create(:pipeline_item, pipeline_stage: start_stage, account: account, contact: conversation.contact)

        described_class.new(rule, account, conversation).perform

        expect(item.reload.pipeline_stage_id).to eq(won_stage.id)
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
        expect(PipelineItem.where(contact_id: conversation.contact_id, pipeline_id: pipeline.id)).to be_empty
      end

      it 'logs the correct message and does not move the card when the target stage does not belong to the pipeline' do
        other_stage = create(:pipeline_stage, account: account)
        rule.update!(actions: [{
                       action_name: 'move_pipeline_item_stage',
                       action_params: [{ pipeline_id: pipeline.id, target_stage_id: other_stage.id }]
                     }])
        item = create(:pipeline_item, pipeline_stage: start_stage, account: account, contact: conversation.contact)

        expect(Rails.logger).to receive(:info).with(/does not belong to/)
        described_class.new(rule, account, conversation).perform

        expect(item.reload.pipeline_stage_id).to eq(start_stage.id)
      end
    end

    describe '#perform with assign_pipeline_item_agent action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        create(:pipeline_member, pipeline: pipeline, user: agent)
        conversation.update!(assignee: agent)
        rule.actions << { action_name: 'assign_pipeline_item_agent',
                          action_params: [{ pipeline_id: pipeline.id, assignee_mode: 'conversation_assignee' }] }
        rule.save!
      end

      it 'assigns the card to the conversation assignee' do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)

        described_class.new(rule, account, conversation).perform

        expect(item.reload.assignee_id).to eq(agent.id)
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end

      it 'assigns an administrator who is not an explicit pipeline member, without raising' do
        admin = create(:user, account: account, role: :administrator)
        conversation.update!(assignee: admin)
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)

        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error

        expect(item.reload.assignee_id).to eq(admin.id)
        expect(Current.account).to be_nil
      end
    end

    describe '#perform with assign_pipeline_item_team action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
      let!(:team) { create(:team, account: account) }

      before do
        conversation.update!(team: team)
        rule.actions << { action_name: 'assign_pipeline_item_team', action_params: [{ pipeline_id: pipeline.id, team_mode: 'conversation_team' }] }
        rule.save!
      end

      it 'assigns the card to the conversation team' do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)

        described_class.new(rule, account, conversation).perform

        expect(item.reload.team_id).to eq(team.id)
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end
    end

    describe '#perform with add_pipeline_item_label action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        create(:label, account: account, title: 'quente', label_type: :pipeline_label)
        rule.actions << { action_name: 'add_pipeline_item_label', action_params: [{ pipeline_id: pipeline.id, labels: ['quente'] }] }
        rule.save!
      end

      it 'adds the labels to the card' do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)

        described_class.new(rule, account, conversation).perform

        expect(item.reload.label_list).to include('quente')
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end
    end

    describe '#perform with remove_pipeline_item_label action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        create(:label, account: account, title: 'quente', label_type: :pipeline_label)
        create(:label, account: account, title: 'frio', label_type: :pipeline_label)
        rule.actions << { action_name: 'remove_pipeline_item_label', action_params: [{ pipeline_id: pipeline.id, labels: ['quente'] }] }
        rule.save!
      end

      it 'removes the labels from the card' do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)
        item.update!(label_list: %w[quente frio])

        described_class.new(rule, account, conversation).perform

        expect(item.reload.label_list).to contain_exactly('frio')
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end
    end

    describe '#perform with update_pipeline_item action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        rule.actions << { action_name: 'update_pipeline_item', action_params: [{ pipeline_id: pipeline.id, title: 'Updated title', value: 250 }] }
        rule.save!
      end

      it 'updates the given subset of fields on the card' do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact, notes: 'keep me')

        described_class.new(rule, account, conversation).perform
        item.reload

        expect(item.title).to eq('Updated title')
        expect(item.value.to_f).to eq(250.0)
        expect(item.notes).to eq('keep me')
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end
    end

    describe '#perform with export_pipeline_item action' do
      let(:pipeline) { create(:pipeline, account: account) }
      let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
      let(:target_pipeline) { create(:pipeline, account: account) }
      let(:target_stage) { target_pipeline.pipeline_stages.find_by(stage_type: :start) }

      before do
        rule.actions << {
          action_name: 'export_pipeline_item',
          action_params: [{ pipeline_id: pipeline.id, target_pipeline_id: target_pipeline.id, target_stage_id: target_stage.id }]
        }
        rule.save!
      end

      it "delegates to Pipelines::ExportItemService to move the card into the target pipeline's stage" do
        item = create(:pipeline_item, pipeline_stage: stage, account: account, contact: conversation.contact)

        described_class.new(rule, account, conversation).perform

        expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
      end

      it 'does nothing when the contact has no card in the pipeline' do
        expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
      end
    end

    describe '#perform with assign_agent action' do
      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        rule.actions << { action_name: 'assign_agent', action_params: ['last_responding_agent'] }
      end

      it 'assigns the conversation to the last responding agent' do
        create(:message, message_type: :outgoing, account: account,
                         inbox: conversation.inbox, conversation: conversation, sender: agent)

        described_class.new(rule, account, conversation).perform

        expect(conversation.reload.assignee).to eq(agent)
      end
    end
  end
end
