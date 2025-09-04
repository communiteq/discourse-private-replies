require 'rails_helper'

describe DiscoursePrivateReplies do
  fab!(:topic_owner) { Fabricate(:user) }
  fab!(:regular_user) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: topic_owner) }
  fab!(:group) { Fabricate(:group) }

  before do
    SiteSetting.private_replies_enabled = true
  end

  describe '.can_see_all_posts?' do
    context 'when user is nil or anonymous' do
      it 'returns false for nil user' do
        expect(described_class.can_see_all_posts?(nil, topic)).to eq(false)
      end

      it 'returns false for anonymous user' do
        anon_user = double('anonymous_user', anonymous?: true)
        expect(described_class.can_see_all_posts?(anon_user, topic)).to eq(false)
      end
    end

    context 'when user is topic owner' do
      it 'returns true' do
        expect(described_class.can_see_all_posts?(topic_owner, topic)).to eq(true)
      end
    end

    context 'when user is topic participant' do
      before do
        SiteSetting.private_replies_participants_can_see_all = true
        Fabricate(:post, topic: topic, user: regular_user)
      end

      it 'returns true when setting is enabled' do
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(true)
      end

      it 'returns false when setting is disabled' do
        SiteSetting.private_replies_participants_can_see_all = false
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end
    end

    context 'when user has required trust level' do
      before do
        SiteSetting.private_replies_min_trust_level_to_see_all = 2
        regular_user.trust_level = 2
      end

      it 'returns true when user meets trust level requirement' do
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(true)
      end

      it 'returns false when user does not meet trust level requirement' do
        regular_user.trust_level = 1
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end

      it 'returns false when trust level setting is disabled' do
        SiteSetting.private_replies_min_trust_level_to_see_all = 5
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end
    end

    context 'when user is in allowed groups' do
      before do
        SiteSetting.private_replies_groups_can_see_all = "#{group.id}|999"
        group.users << regular_user
      end

      it 'returns true when user is in allowed group' do
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(true)
      end

      it 'returns false when user is not in allowed group' do
        group.users.clear
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end
    end

    context 'when user is in same primary group as topic owner' do
      let(:primary_group) { Fabricate(:group) }

      before do
        SiteSetting.private_replies_topic_starter_primary_group_can_see_all = true
        topic_owner.primary_group = primary_group
        topic_owner.save!
        primary_group.users << topic_owner
        primary_group.users << regular_user
      end

      it 'returns true when user shares primary group with topic owner' do
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(true)
      end

      it 'returns false when setting is disabled' do
        SiteSetting.private_replies_topic_starter_primary_group_can_see_all = false
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end

      it 'returns false when topic owner has no primary group' do
        topic_owner.primary_group = nil
        topic_owner.save!
        expect(described_class.can_see_all_posts?(regular_user, topic)).to eq(false)
      end
    end
  end

  describe '.can_see_post_if_author_among' do
    let(:special_group) { Fabricate(:group) }
    let(:group_user) { Fabricate(:user) }

    before do
      SiteSetting.private_replies_see_all_from_groups = "#{special_group.id}"
      special_group.users << group_user
    end

    it 'returns array with users from special groups' do
      result = described_class.can_see_post_if_author_among(regular_user, topic)
      expect(result).to include(group_user.id)
    end

    it 'includes topic owner id when topic is present' do
      result = described_class.can_see_post_if_author_among(regular_user, topic)
      expect(result).to include(topic_owner.id)
    end

    it 'includes current user id when user is not anonymous' do
      result = described_class.can_see_post_if_author_among(regular_user, topic)
      expect(result).to include(regular_user.id)
    end

    it 'returns unique user ids' do
      # Add regular_user to special group to create potential duplicate
      special_group.users << regular_user
      result = described_class.can_see_post_if_author_among(regular_user, topic)
      expect(result.count(regular_user.id)).to eq(1)
    end

    it 'handles nil topic gracefully' do
      result = described_class.can_see_post_if_author_among(regular_user, nil)
      expect(result).to include(regular_user.id, group_user.id)
      expect(result).not_to include(topic_owner.id)
    end
  end
end