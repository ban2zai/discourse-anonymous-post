# frozen_string_literal: true

# name: discourse-anonymous-post
# version: 0.3.0
# authors: github.com/fokx
# url: https://github.com/fokx/discourse-anonymous-post

%i[common mobile].each do |layout|
  register_asset "stylesheets/anonymous-post/#{layout}.scss", layout
end

enabled_site_setting :anonymous_post_enabled

after_initialize do
  register_svg_icon "ghost"
  add_permitted_post_create_param(:is_anonymous_post)
  register_post_custom_field_type("is_anonymous_post", :integer)
  register_topic_custom_field_type("is_anonymous_topic", :integer)

  # --- Helpers ---

  anon_avatar = "/letter_avatar_proxy/v4/letter/a/b3b5b3/{size}.png"

  is_anon_post = ->(post_obj) { post_obj.custom_fields["is_anonymous_post"].to_i == 1 }
  is_anon_topic = ->(topic_obj) { topic_obj.custom_fields["is_anonymous_topic"].to_i == 1 }

  anonymous_user_hash = lambda {
    {
      id: -1,
      username: "anonymous",
      name: I18n.t("js.anonymous_post.anonymous_name"),
      avatar_template: anon_avatar,
    }
  }

  # --- Post creation: save custom fields ---

  on(:post_created) do |post, opts|
    value = opts[:is_anonymous_post].to_i
    if value.positive?
      Rails.logger.warn("[ANON-POST] post_created: post_id=#{post.id}, post_number=#{post.post_number}, is_anonymous_post=#{value}")

      post.custom_fields["is_anonymous_post"] = value
      post.save_custom_fields(true)

      if post.post_number == 1
        post.topic.custom_fields["is_anonymous_topic"] = 1
        post.topic.save_custom_fields(true)
        Rails.logger.warn("[ANON-POST] topic #{post.topic.id} marked as anonymous")
      end
    end
  end

  # --- PostSerializer overrides ---

  add_to_serializer(:post, :is_anonymous_post) do
    object.custom_fields["is_anonymous_post"].to_i
  end

  add_to_serializer(:post, :username) do
    if is_anon_post.call(object) && !scope.is_admin?
      "anonymous"
    else
      object.user&.username
    end
  end

  add_to_serializer(:post, :display_username) do
    if is_anon_post.call(object) && !scope.is_admin?
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :name) do
    if is_anon_post.call(object) && !scope.is_admin?
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :avatar_template) do
    if is_anon_post.call(object) && !scope.is_admin?
      anon_avatar
    else
      object.user&.avatar_template
    end
  end

  add_to_serializer(:post, :user_id) do
    if is_anon_post.call(object) && !scope.is_admin?
      nil
    else
      object.user_id
    end
  end

  # --- TopicViewSerializer: topic-level user_id ---

  add_to_serializer(:topic_view, :user_id) do
    topic = object.topic
    if is_anon_topic.call(topic) && !scope.is_admin?
      Rails.logger.warn("[ANON-POST] TopicViewSerializer: hiding user_id for topic #{topic.id}")
      nil
    else
      topic.user_id
    end
  end

  # --- TopicViewDetailsSerializer: created_by, last_poster, participants ---

  add_to_serializer(:topic_view_details, :created_by) do
    topic = object.topic
    if is_anon_topic.call(topic) && !scope.is_admin?
      Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing created_by for topic #{topic.id}")
      anonymous_user_hash.call
    else
      BasicUserSerializer.new(object.topic_creator, scope: scope, root: false)
    end
  end

  add_to_serializer(:topic_view_details, :last_poster) do
    topic = object.topic
    last_poster_user = object.topic_last_poster

    # Anonymize last_poster if: topic is anonymous AND the last poster is the OP,
    # OR if the last poster made an anonymous post in this topic
    should_anonymize = false
    if !scope.is_admin?
      if is_anon_topic.call(topic) && last_poster_user&.id == topic.user_id
        should_anonymize = true
      end
      # Also check if last post itself is anonymous
      last_post = topic.posts.order(post_number: :desc).first
      if last_post && is_anon_post.call(last_post)
        should_anonymize = true
      end
    end

    if should_anonymize
      Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing last_poster for topic #{topic.id}")
      anonymous_user_hash.call
    else
      BasicUserSerializer.new(last_poster_user, scope: scope, root: false)
    end
  end

  add_to_serializer(:topic_view_details, :participants) do
    topic = object.topic
    participants = object.post_counts_by_user.map do |user, count|
      # Check if this user has only anonymous posts in this topic
      user_anon_posts = topic.posts.where(user_id: user.id)
        .select { |p| is_anon_post.call(p) }

      user_all_posts = topic.posts.where(user_id: user.id).count
      all_anonymous = user_anon_posts.length == user_all_posts

      if all_anonymous && !scope.is_admin?
        Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing participant #{user.id} in topic #{topic.id}")
        hash = anonymous_user_hash.call
        hash[:post_count] = count
        hash
      else
        serializer = UserWithCountSerializer.new(user, scope: scope, root: false)
        serializer.post_count = count
        serializer
      end
    end

    participants
  end

  # --- TopicListItemSerializer: posters in topic list ---

  add_to_serializer(:topic_list_item, :posters) do
    topic = object

    # Load original posters using the default method
    original_posters = object.posters || []

    if is_anon_topic.call(topic) && !scope.is_admin?
      Rails.logger.warn("[ANON-POST] TopicListItemSerializer: anonymizing posters for topic #{topic.id}")

      original_posters.map do |poster|
        # Original Poster gets anonymized
        if poster.description&.include?("Original Poster")
          OpenStruct.new(
            user: OpenStruct.new(anonymous_user_hash.call),
            description: poster.description,
            extras: poster.extras,
            primary_group: nil,
          )
        else
          poster
        end
      end
    else
      original_posters
    end
  end

  # --- UserAction: hide anonymous posts from other users' activity ---

  add_to_class(:UserAction, :is_anonymous_action?) do
    return false unless post_id.present?
    post = Post.find_by(id: post_id)
    return false unless post
    post.custom_fields["is_anonymous_post"].to_i == 1
  end

  add_to_serializer(:user_action, :include_self?) do
    # Hide anonymous actions from everyone except the author and admins
    if object.respond_to?(:post_id) && object.post_id.present?
      post = Post.find_by(id: object.post_id)
      if post && post.custom_fields["is_anonymous_post"].to_i == 1
        # Only show to the author or admins
        return scope.is_admin? || scope.user&.id == post.user_id
      end
    end
    true
  end
end
