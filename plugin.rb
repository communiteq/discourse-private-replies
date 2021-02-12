# name: discourse-private-replies
# about: Communiteq private replies plugin
# version: 1.1
# authors: richard@communiteq.com
# url: https://www.communiteq.com/discoursehosting/kb/discourse-private-replies-plugin

enabled_site_setting :private_replies_enabled

register_svg_icon "user-secret" if respond_to?(:register_svg_icon)

load File.expand_path('../lib/discourse_private_replies/engine.rb', __FILE__)

after_initialize do
  
  # hide posts from the /raw/tid/pid route
  module ::PostGuardian
    alias_method :org_can_see_post?, :can_see_post?

    def can_see_post?(post)
      return true if is_admin? 

      allowed = org_can_see_post?(post)
      return false unless allowed

      if SiteSetting.private_replies_enabled && post.topic.custom_fields.keys.include?('private_replies') && post.topic.custom_fields['private_replies']
        userids = Group.find(Group::AUTO_GROUPS[:staff]).users.pluck(:id) + [ post.topic.user.id ]
        userids = userids + [ @user.id ] unless @user.anonymous?
        return false unless userids.include? post.user.id
      end
      
      true
    end
  end

  # hide posts from the regular topic stream
  module PatchTopicView

    # hide posts at the lowest level
    def unfiltered_posts
      result = super
      
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user || @topic.user.id != @user.id    # Topic starter can see it all
          userids = Group.find(Group::AUTO_GROUPS[:staff]).users.pluck(:id) + [ @topic.user.id ] 
          userids = userids + [ @user.id ] if @user
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
        if !@user || @topic.user.id != @user.id    # Topic starter can see it all
          userids = Group.find(Group::AUTO_GROUPS[:staff]).users.pluck(:id) + [ @topic.user.id ] 
          userids = userids + [ @user.id ] if @user
          @posts = @posts.where('(posts.post_number = 1 OR posts.user_id IN (?))', userids)
        end
      end
      @posts
    end
  end

  # hide posts from search results
  module PatchSearch
  
    def execute(readonly_mode)
      super

      if SiteSetting.private_replies_enabled
        userids = Group.find(Group::AUTO_GROUPS[:staff]).users.pluck(:id) 
        userids = userids + [ @guardian.user.id ] if @guardian.user
        
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
        if SiteSetting.private_replies_enabled
          userids = Group.find(Group::AUTO_GROUPS[:staff]).users.pluck(:id) 
          userids = userids + [ guardian.user.id ] if guardian.user
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

  class ::TopicView
    prepend PatchTopicView
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

end

