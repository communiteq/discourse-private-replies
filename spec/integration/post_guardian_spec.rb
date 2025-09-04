require 'rails_helper'

describe PostGuardian do
  let(:admin) { Fabricate(:admin) }
  let(:user) { Fabricate(:user) }
  let(:topic_owner) { Fabricate(:user) }
  let(:topic) { Fabricate(:topic, user: topic_owner) }
  let(:post) { Fabricate(:post, topic: topic, user: topic_owner) }
  let(:guardian) { Guardian.new(user) }
  let(:admin_guardian) { Guardian.new(admin) }

  before do
    SiteSetting.private_replies_enabled = true
  end

  describe '#can_see_post?' do
    context 'when private replies is disabled' do
      before { SiteSetting.private_replies_enabled = false }

      it 'uses original behavior' do
        expect(guardian.can_see_post?(post)).to eq(true)
      end
    end

    context 'when topic does not have private replies enabled' do
      it 'uses original behavior' do
        expect(guardian.can_see_post?(post)).to eq(true)
      end
    end

    context 'when topic has private replies enabled' do
      before do
        topic.custom_fields['private_replies'] = true
        topic.save_custom_fields
      end

      it 'allows admin to see all posts' do
        expect(admin_guardian.can_see_post?(post)).to eq(true)
      end

      it 'allows topic owner to see posts' do
        owner_guardian = Guardian.new(topic_owner)
        expect(owner_guardian.can_see_post?(post)).to eq(true)
      end

      context 'when user cannot see all posts' do
        let(:other_user) { Fabricate(:user) }
        let(:other_post) { Fabricate(:post, topic: topic, user: other_user) }

        it 'hides posts from users not in allowed list' do
          expect(guardian.can_see_post?(other_post)).to eq(false)
        end

        it 'shows posts from users in allowed groups' do
          group = Fabricate(:group)
          SiteSetting.private_replies_see_all_from_groups = group.id.to_s
          group.users << other_user
          
          expect(guardian.can_see_post?(other_post)).to eq(true)
        end

        it 'shows user their own posts' do
          user_post = Fabricate(:post, topic: topic, user: user)
          expect(guardian.can_see_post?(user_post)).to eq(true)
        end
      end
    end
  end
end