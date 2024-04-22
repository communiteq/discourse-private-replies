# name: discourse-private-replies
# about: Communiteq private replies plugin
# version: 1.4
# authors: Communiteq
# url: https://www.communiteq.com/discoursehosting/kb/discourse-private-replies-plugin
# meta_topic_id: 146712

enabled_site_setting :private_replies_enabled

register_svg_icon "user-secret" if respond_to?(:register_svg_icon)

load File.expand_path('../lib/discourse_private_replies/engine.rb', __FILE__)

module ::DiscoursePrivateReplies
  def DiscoursePrivateReplies.can_see_all_posts?(user, topic)
    return false if user.anonymous? # anonymous users don't have the id method

    return true if topic && user.id == topic.user.id

    min_trust_level = SiteSetting.private_replies_min_trust_level_to_see_all
    if (min_trust_level >= 0) && (min_trust_level < 5)
      return true if user.has_trust_level?(TrustLevel[min_trust_level])
    end

    return true if (SiteSetting.private_replies_groups_can_see_all.split('|').map(&:to_i) & user.groups.pluck(:id)).count > 0

    if SiteSetting.private_replies_topic_starter_primary_group_can_see_all && topic
      groupids = Group.find(topic.user.primary_group_id).users.pluck(:id) if topic.user && !topic.user.anonymous?
      return true if groupids.include? user.id
    end

    false
  end

  def DiscoursePrivateReplies.can_see_post_if_author_among(user, topic)
    userids = []
    Group.where("id in (?)", SiteSetting.private_replies_see_all_from_groups.split('|')).each do |g|
      userids += g.users.pluck(:id)
    end
    userids = userids + [ topic.user.id ] if topic
    userids = userids + [ user.id ] if user && !user.anonymous? # anonymous users don't have the id method
    return userids.uniq
  end
end

after_initialize do

  # hide posts from the /raw/tid/pid route
  module ::PostGuardian
    alias_method :org_can_see_post?, :can_see_post?

    def can_see_post?(post)
      return true if is_admin?

      allowed = org_can_see_post?(post)
      return false unless allowed

      if SiteSetting.private_replies_enabled && post.topic.custom_fields.keys.include?('private_replies') && post.topic.custom_fields['private_replies']
        return true if DiscoursePrivateReplies.can_see_all_posts?(@user, post.topic)

        userids = DiscoursePrivateReplies.can_see_post_if_author_among(@user, post.topic)
        return false unless userids.include? post.user.id
      end

      true
    end
  end

  # hide posts from the regular topic stream
  module PatchTopicView

    def participants
      result = super
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user || !DiscoursePrivateReplies.can_see_all_posts?(@user, @topic)
          userids = DiscoursePrivateReplies.can_see_post_if_author_among(@user, @topic)
          result.select! { |key, _| userids.include?(key) }
        end
      end
      result
    end

    # hide posts at the lowest level
    def unfiltered_posts
      result = super

      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user || !DiscoursePrivateReplies.can_see_all_posts?(@user, @topic)
          userids = DiscoursePrivateReplies.can_see_post_if_author_among(@user, @topic)
          result = result.where('(posts.post_number = 1 OR posts.user_id IN (?))', userids)
        end
      end
      result
    end

    # filter posts_by_ids does not seem to use unfiltered_posts ?! WHY...
    # so we need to filter that separately
    def filter_posts_by_ids(post_ids)
      @posts = super(post_ids)
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user || !DiscoursePrivateReplies.can_see_all_posts?(@user, @topic)
          userids = DiscoursePrivateReplies.can_see_post_if_author_among(@user, @topic)
          @posts = @posts.where('(posts.post_number = 1 OR posts.user_id IN (?))', userids)
        end
      end
      @posts
    end
  end

  module PatchTopicViewDetailsSerializer
    def last_poster
      if SiteSetting.private_replies_enabled && object.topic.custom_fields.keys.include?('private_replies') && object.topic.custom_fields['private_replies']
        if !scope.user || !DiscoursePrivateReplies.can_see_all_posts?(scope.user, object.topic)
          userids = DiscoursePrivateReplies.can_see_post_if_author_among(scope.user, object.topic)
          return object.topic.user unless !userids.include? object.topic.last_poster
        end
      end
      object.topic.last_poster
    end
  end

  module PatchTopicPostersSummary
    def initialize(topic, options = {})
      super
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        @filter_userids = DiscoursePrivateReplies.can_see_post_if_author_among(@user, @topic)
      else
        @filter_userids = nil
      end
    end

    def summary
      result = super
      if @filter_userids
        result.select! { |v| @filter_userids.include?(v.user.id) }
      end
      result
    end
  end

  # hide posts from search results
  module PatchSearch
    def execute(readonly_mode: @readonly_mode)
      super

      if SiteSetting.private_replies_enabled && !DiscoursePrivateReplies.can_see_all_posts?(@guardian.user, nil)
        userids = DiscoursePrivateReplies.can_see_post_if_author_among(@guardian.user, nil)

        protected_topics = TopicCustomField.where(:name => 'private_replies').where(:value => true).pluck(:topic_id)

        @results.posts.delete_if do |post|
          next false unless protected_topics.include? post.topic_id # leave unprotected topics alone
          next false if userids.include? post.user_id               # show staff and own posts
          next false if post.user_id == post.topic.user_id          # show topic starter posts
          true
        end
      end

      @results
    end
  end

  # hide posts from user profile -> activity
  class ::UserAction
    module PrivateRepliesApplyCommonFilters
      def apply_common_filters(builder, user_id, guardian, ignore_private_messages=false)
        if SiteSetting.private_replies_enabled && !DiscoursePrivateReplies.can_see_all_posts?(guardian.user, nil)
          userids = DiscoursePrivateReplies.can_see_post_if_author_among(guardian.user, nil)
          userid_list = userids.join(',')

          protected_topic_list = TopicCustomField.where(:name => 'private_replies').where(:value => true).pluck(:topic_id).join(',')

          if !protected_topic_list.empty?
            builder.where("( (a.target_topic_id not in (#{protected_topic_list})) OR (a.acting_user_id = t.user_id) OR (a.acting_user_id in (#{userid_list})) )")
          end
        end
        super(builder, user_id, guardian, ignore_private_messages)
      end
    end
    singleton_class.prepend PrivateRepliesApplyCommonFilters
  end

  # hide posts from digest and mlm-summary
  class ::Topic
    class << self
      alias_method :original_for_digest, :for_digest

      # either the topic is unprotected, or it is the first post number, or it is the user's own topic, or the users posts can be seen
      # @TODO this does not implement private_replies_topic_starter_primary_group_can_see_all
      def for_digest(user, since, opts = nil)
        topics = original_for_digest(user, since, opts)
        if SiteSetting.private_replies_enabled && !DiscoursePrivateReplies.can_see_all_posts?(user, nil)
          userid_list = DiscoursePrivateReplies.can_see_post_if_author_among(user, nil).join(',')
          protected_topic_list = TopicCustomField.where(:name => 'private_replies').where(:value => true).pluck(:topic_id).join(',')
          topics = topics.where("(topics.id NOT IN (#{protected_topic_list}) OR posts.post_number = 1 OR topics.user_id = #{user.id} OR posts.user_id IN (#{userid_list}))")
        end
        topics
      end
    end
  end

  class ::TopicView
    prepend PatchTopicView
  end

  class ::TopicPostersSummary
    prepend PatchTopicPostersSummary
  end

  class ::TopicViewDetailsSerializer
    prepend PatchTopicViewDetailsSerializer
  end

  class ::Search
    prepend PatchSearch
  end

  Topic.register_custom_field_type('private_replies', :boolean)
  add_to_serializer :topic_view, :private_replies do
    object.topic.custom_fields['private_replies']
  end

  Discourse::Application.routes.append do
    mount ::DiscoursePrivateReplies::Engine, at: "/private_replies"
  end

  DiscourseEvent.on(:topic_created) do |topic|
    if SiteSetting.private_replies_enabled
      if (SiteSetting.private_replies_on_selected_categories_only == false) || (topic&.category&.custom_fields&.dig('private_replies_enabled'))
        if topic&.category&.custom_fields&.dig('private_replies_default_enabled')
          topic.custom_fields['private_replies'] = true
          topic.save_custom_fields
        end
      end
    end
  end

  Site.preloaded_category_custom_fields << 'private_replies_default_enabled'
  Site.preloaded_category_custom_fields << 'private_replies_enabled'
end

