# name: discourse-private-replies
# about: DiscourseHosting private replies plugin
# version: 0.1
# authors: richard@discoursehosting.com
# url: https://www.discoursehosting.com/

after_initialize do

  # disable /raw/tid/pid route
  module ::PostGuardian
    alias_method :org_can_see_post?, :can_see_post?

    def can_see_post?(post)
      #comment below for easy testing
      #return true if is_admin? 

      allowed = org_can_see_post?(post)
      return false unless allowed

      userids = Group.find_by_name('staff').users.pluck(:id) + [ post.topic.user.id ] + [ @user.id ]
      return false unless userids.include? post.user.id

      true
    end
  end

  module PatchTopicView

    # hide posts at the lowest level
    def unfiltered_posts
      result = super

      if @topic.user.id != @user.id # Topic starter can see it all
        puts "UFP #{@user.id} #{@topic.id}"
        userids = Group.find_by_name('staff').users.pluck(:id) + [ @topic.user.id ] + [ @user.id ]
        result = result.where('posts.post_number = 1 OR posts.user_id IN (?)', userids)
      end

      result
    end

    #def setup_filtered_postsx
    #  super

      # RGJ this shows 'hidden posts' but if they are clicked it will not prevent them from showing
    #  userids = Group.find_by_name('staff').users.pluck(:id) + [ @topic.user.id ] + [ @user.id ]
    #  @filtered_posts = @filtered_posts.where('posts.post_number = 1 OR posts.user_id IN (?)', userids)
    #  @contains_gaps = true

    #end
  end

  class ::TopicView
    prepend PatchTopicView
  end

end

