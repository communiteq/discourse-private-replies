require 'rails_helper'

describe TopicView do
  let(:user) { Fabricate(:user) }
  let(:topic_owner) { Fabricate(:user) }
  let(:topic) { Fabricate(:topic, user: topic_owner) }
  let(:allowed_user) { Fabricate(:user) }
  let(:restricted_user) { Fabricate(:user) }

  before do
    SiteSetting.private_replies_enabled = true
    topic.custom_fields['private_replies'] = true
    topic.save_custom_fields
    
    # Create posts from different users
    Fabricate(:post, topic: topic, user: topic_owner, post_number: 1)
    Fabricate(:post, topic: topic, user: allowed_user, post_number: 2)
    Fabricate(:post, topic: topic, user: restricted_user, post_number: 3)
    
    # Setup allowed user in special group
    group = Fabricate(:group)
    SiteSetting.private_replies_see_all_from_groups = group.id.to_s
    group.users << allowed_user
  end

  describe '#unfiltered_posts' do
    it 'shows all posts to topic owner' do
      topic_view = TopicView.new(topic, topic_owner)
      expect(topic_view.unfiltered_posts.count).to eq(3)
    end

    it 'filters posts for regular users' do
      topic_view = TopicView.new(topic, user)
      posts = topic_view.unfiltered_posts
      
      # Should see: topic starter post + allowed_user post + own posts
      expect(posts.where(user_id: restricted_user.id).count).to eq(0)
      expect(posts.where('post_number = 1 OR user_id = ?', allowed_user.id).count).to eq(2)
    end

    it 'shows own posts to user' do
      user_post = Fabricate(:post, topic: topic, user: user, post_number: 4)
      topic_view = TopicView.new(topic, user)
      posts = topic_view.unfiltered_posts
      
      expect(posts.where(user_id: user.id).count).to eq(1)
    end
  end

  describe '#participants' do
    it 'filters participants for restricted users' do
      topic_view = TopicView.new(topic, user)
      participants = topic_view.participants
      
      expect(participants.keys).to include(topic_owner.id, allowed_user.id)
      expect(participants.keys).not_to include(restricted_user.id)
    end

    it 'shows all participants to topic owner' do
      topic_view = TopicView.new(topic, topic_owner)
      participants = topic_view.participants
      
      expect(participants.keys).to include(topic_owner.id, allowed_user.id, restricted_user.id)
    end
  end
end