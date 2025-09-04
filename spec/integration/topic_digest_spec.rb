require 'rails_helper'

describe Topic do
  fab!(:user) { Fabricate(:user) }
  fab!(:topic_owner) { Fabricate(:user) }
  fab!(:allowed_user) { Fabricate(:user) }
  fab!(:restricted_user) { Fabricate(:user) }
  fab!(:group) { Fabricate(:group) }

  before do
    SiteSetting.private_replies_enabled = true

    # Setup allowed user
    SiteSetting.private_replies_see_all_from_groups = group.id.to_s
    group.users << allowed_user

    # Configure digest settings to make topics eligible
    SiteSetting.digest_min_excerpt_length = 5
    SiteSetting.digest_topics = 10
    SiteSetting.suppress_digest_email_after_days = 365
    SiteSetting.default_email_digest_frequency = 24*60*7 # weekly
  end

  describe '.for_digest' do
    let!(:topic1) { Fabricate(:topic, user: topic_owner, title: "First digest topic by owner", created_at: 3.days.ago) }
    let!(:topic2) { Fabricate(:topic, user: topic_owner, title: "Second digest topic by owner", created_at: 3.days.ago) }
    let!(:topic3) { Fabricate(:topic, user: topic_owner, title: "Third digest topic by owner", created_at: 3.days.ago) }

    before do
      # Enable private replies on all topics
      [topic1, topic2, topic3].each do |topic|
        topic.custom_fields['private_replies'] = true
        topic.save_custom_fields
      end

      # Create posts 3 days ago to make them digest-eligible
      freeze_time(3.days.ago) do
        # Create first posts
        @topic1_first = Fabricate(:post, topic: topic1, user: topic_owner, raw: "First post content for digest topic 1")
        @topic2_first = Fabricate(:post, topic: topic2, user: topic_owner, raw: "First post content for digest topic 2")
        @topic3_first = Fabricate(:post, topic: topic3, user: topic_owner, raw: "First post content for digest topic 3")

        # Create replies from different users
        @topic1_reply_owner = Fabricate(:post, topic: topic1, user: topic_owner, raw: "Digest reply by topic owner")
        @topic2_reply_allowed = Fabricate(:post, topic: topic2, user: allowed_user, raw: "Digest reply by allowed user")
        @topic3_reply_restricted = Fabricate(:post, topic: topic3, user: restricted_user, raw: "Digest reply by restricted user")
      end

      # Update topic stats to make them digest-worthy
      [topic1, topic2, topic3].each do |topic|
        topic.update!(
          posts_count: topic.posts.count,
          last_posted_at: 2.days.ago,
          bumped_at: 2.days.ago,
          views: 10,
          like_count: 2
        )
      end
    end

    it 'includes all topics in digest regardless of reply permissions' do
      # Since digests show topic titles and first posts (which are always visible),
      # private replies shouldn't affect which topics appear in digest

      [topic_owner, allowed_user, user, restricted_user].each do |test_user|
        topics = Topic.for_digest(test_user, 1.week.ago).to_a
        topic_ids = topics.map(&:id)

        # All users should see all topics since first posts are always visible
        expect(topic_ids).to include(topic1.id, topic2.id, topic3.id)
      end
    end

    it 'shows digest works when private replies is disabled' do
      SiteSetting.private_replies_enabled = false

      topics = Topic.for_digest(user, 1.week.ago).to_a
      topic_ids = topics.map(&:id)

      expect(topic_ids).to include(topic1.id, topic2.id, topic3.id)
    end

    it 'first posts are always accessible in digest topics' do
      topics = Topic.for_digest(user, 1.week.ago).to_a

      # Verify that first posts exist and are accessible
      topics.each do |topic|
        first_post = topic.first_post
        expect(first_post).to be_present
        expect(first_post.raw).to be_present
      end
    end

    it 'does not expose private replies in digest content' do
      # Test what happens when we try to access reply posts through digest topics
      topics = Topic.for_digest(user, 1.week.ago).to_a

      # Find our test topics
      test_topics = topics.select { |t| [topic1.id, topic2.id, topic3.id].include?(t.id) }
      expect(test_topics).not_to be_empty

      test_topics.each do |topic|
        # First posts should always be accessible
        first_post = topic.first_post
        expect(first_post).to be_present
        expect(first_post.raw).to be_present

        # Check if the topic has reply posts
        reply_posts = topic.posts.where('post_number > 1')

        if reply_posts.any?
          puts "Topic #{topic.id} has #{reply_posts.count} replies"

          # Test if restricted user can see reply posts
          guardian = Guardian.new(user)

          reply_posts.each do |post|
            can_see = guardian.can_see_post?(post)
            puts "  Reply by #{post.user.username}: can_see = #{can_see}"

            # Based on your plugin logic:
            # - Should see replies by topic_owner and allowed_user
            # - Should NOT see replies by restricted_user
            if post.user == topic_owner || post.user == allowed_user
              expect(can_see).to be(true), "Should see reply by #{post.user.username}"
            elsif post.user == restricted_user
              expect(can_see).to be(false), "Should NOT see reply by #{post.user.username}"
            end
          end
        end
      end
    end

    it 'debug: shows what posts are accessible in digest topics' do
      topics = Topic.for_digest(user, 1.week.ago).to_a
      guardian = Guardian.new(user)

      puts "\n=== DIGEST POST ACCESS DEBUG ==="
      puts "User: #{user.username} (regular user)"

      topics.each do |topic|
        next unless [topic1.id, topic2.id, topic3.id].include?(topic.id)

        puts "Topic #{topic.id}: #{topic.title}"

        topic.posts.order(:post_number).each do |post|
          can_see = guardian.can_see_post?(post)
          puts "  Post ##{post.post_number} by #{post.user.username}: #{can_see ? 'VISIBLE' : 'HIDDEN'}"
          puts "    Content: #{post.raw.truncate(50)}"
        end
      end
      puts "===================================\n"

      # This test is just for debugging
      expect(true).to be true
    end
  end
end