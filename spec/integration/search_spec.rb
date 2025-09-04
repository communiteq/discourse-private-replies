require 'rails_helper'

RSpec.describe Search do
  fab!(:user) { Fabricate(:user) }
  fab!(:topic_owner) { Fabricate(:user) }
  fab!(:allowed_user) { Fabricate(:user) }
  fab!(:restricted_user) { Fabricate(:user) }
  fab!(:group) { Fabricate(:group) }

  # All topics should be owned by topic_owner to test private REPLIES
  let(:topic1) { Fabricate(:topic, user: topic_owner, title: "First topic by topic owner") }
  let(:topic2) { Fabricate(:topic, user: topic_owner, title: "Second topic by topic owner") }
  let(:topic3) { Fabricate(:topic, user: topic_owner, title: "Third topic by topic owner") }

  before do
    SearchIndexer.enable

    # Setup group membership
    group.users << allowed_user
    SiteSetting.private_replies_see_all_from_groups = group.id.to_s

    # Enable private replies on all topics
    [topic1, topic2, topic3].each do |topic|
      topic.custom_fields['private_replies'] = true
      topic.save_custom_fields
    end

    # Create FIRST POSTS explicitly for each topic
    @topic1_first_post = Fabricate(:post, topic: topic1, user: topic_owner, post_number: 1, raw: "First post content for topic 1")
    @topic2_first_post = Fabricate(:post, topic: topic2, user: topic_owner, post_number: 1, raw: "First post content for topic 2")
    @topic3_first_post = Fabricate(:post, topic: topic3, user: topic_owner, post_number: 1, raw: "First post content for topic 3")

    # Create REPLIES from different users to the same topics owned by topic_owner
    @topic1_reply_by_owner = Fabricate(:post, topic: topic1, user: topic_owner, post_number: 2, raw: "searchable reply by topic owner")
    @topic2_reply_by_allowed = Fabricate(:post, topic: topic2, user: allowed_user, post_number: 2, raw: "searchable reply by allowed user")
    @topic3_reply_by_restricted = Fabricate(:post, topic: topic3, user: restricted_user, post_number: 2, raw: "searchable reply by restricted user")

    # Index all posts
    [@topic1_first_post, @topic2_first_post, @topic3_first_post,
     @topic1_reply_by_owner, @topic2_reply_by_allowed, @topic3_reply_by_restricted].each do |post|
      SearchIndexer.index(post, force: true)
    end
  end

  after do
    SearchIndexer.disable
  end

  context 'when private replies is disabled globally' do
    before do
      SiteSetting.private_replies_enabled = false
    end

    it 'shows replies from all topics when plugin is disabled' do
      search = Search.new("searchable", guardian: Guardian.new(user))
      results = search.execute

      topic_ids = results.posts.map(&:topic_id)
      expect(topic_ids).to include(topic1.id, topic2.id, topic3.id)
    end
  end

  context 'when private replies is enabled globally' do
    before do
      SiteSetting.private_replies_enabled = true
    end

    it 'filters search results to show only allowed replies' do
      search = Search.new("searchable", guardian: Guardian.new(user))
      results = search.execute

      topic_ids = results.posts.map(&:topic_id)
      post_ids = results.posts.map(&:id)

      # Should see replies from topic owner and allowed user, but not restricted user
      expect(topic_ids).to include(topic1.id, topic2.id)
      expect(topic_ids).not_to include(topic3.id)

      expect(post_ids).to include(@topic1_reply_by_owner.id, @topic2_reply_by_allowed.id)
      expect(post_ids).not_to include(@topic3_reply_by_restricted.id)
    end

    it 'shows all results to topic owners' do
      search = Search.new("searchable", guardian: Guardian.new(topic_owner))
      results = search.execute

      topic_ids = results.posts.map(&:topic_id)
      expect(topic_ids).to include(topic1.id, topic2.id, topic3.id)
    end

    it 'allows restricted users to find their own replies' do
      search = Search.new("searchable", guardian: Guardian.new(restricted_user))
      results = search.execute

      topic_ids = results.posts.map(&:topic_id)
      post_ids = results.posts.map(&:id)

      # Should see replies from topic owner, allowed user, and their own reply
      expect(topic_ids).to include(topic1.id, topic2.id, topic3.id)
      expect(post_ids).to include(@topic1_reply_by_owner.id, @topic2_reply_by_allowed.id, @topic3_reply_by_restricted.id)
    end
  end

  context 'topic starter posts are always visible' do
    before do
      SiteSetting.private_replies_enabled = true
    end

    it 'shows first posts even from restricted users' do
      # Update the existing first post content to be uniquely searchable
      @topic3_first_post.update!(raw: "unique_first_post_content from topic owner")
      SearchIndexer.index(@topic3_first_post, force: true)

      search = Search.new("unique_first_post_content", guardian: Guardian.new(user))
      results = search.execute

      # Should find the first post since first posts are always visible
      expect(results.posts.map(&:id)).to include(@topic3_first_post.id)
    end
  end
end