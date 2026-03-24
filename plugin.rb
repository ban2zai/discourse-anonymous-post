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

  # Preload custom fields to avoid N+1 queries (HasCustomFields::NotPreloadedError)
  TopicList.preloaded_custom_fields << "is_anonymous_topic"

  # --- Shared helper module ---

  module ::AnonymousPostHelper
    ANON_USERNAME = "anonymous"
    ANON_AVATAR_FALLBACK = "/letter_avatar_proxy/v4/letter/a/b3b5b3/{size}.png"

    def self.anonymous_user
      @anonymous_user ||= User.find_by(username: ANON_USERNAME)
    end

    def self.reset_cache!
      @anonymous_user = nil
    end

    def self.anonymous_user_hash
      user = anonymous_user
      if user
        {
          id: user.id,
          username: user.username,
          name: user.name || I18n.t("js.anonymous_post.anonymous_name"),
          avatar_template: user.avatar_template,
        }
      else
        {
          id: -1,
          username: ANON_USERNAME,
          name: I18n.t("js.anonymous_post.anonymous_name"),
          avatar_template: ANON_AVATAR_FALLBACK,
        }
      end
    end

    # Returns a serializer-compatible object (BasicUserSerializer needs read_attribute_for_serialization)
    def self.anonymous_user_object
      data = anonymous_user_hash
      obj = OpenStruct.new(
        id: data[:id],
        username: data[:username],
        name: data[:name],
        avatar_template: data[:avatar_template],
        primary_group_id: nil,
        flair_group_id: nil,
      )
      def obj.read_attribute_for_serialization(attr)
        send(attr)
      end
      obj
    end

    def self.anon_post?(post_obj)
      post_obj.custom_fields["is_anonymous_post"].to_i == 1
    end

    # Safe check via direct DB query — avoids NotPreloadedError
    def self.anon_post_by_id?(post_id)
      PostCustomField.exists?(post_id: post_id, name: "is_anonymous_post", value: "1")
    end

    # Get all user_ids that have anonymous posts in a given topic
    def self.anon_user_ids_in_topic(topic_id)
      PostCustomField
        .where(name: "is_anonymous_post", value: "1")
        .joins("INNER JOIN posts ON posts.id = post_custom_fields.post_id")
        .where("posts.topic_id = ?", topic_id)
        .pluck("posts.user_id")
        .uniq
    end

    def self.anon_topic?(topic_obj)
      topic_obj.custom_fields["is_anonymous_topic"].to_i == 1
    end
  end

  # --- Post creation: save custom fields ---

  on(:post_created) do |post, opts|
    value = opts[:is_anonymous_post].to_i
    if value.positive?
      post.custom_fields["is_anonymous_post"] = value
      post.save_custom_fields(true)

      if post.post_number == 1
        post.topic.custom_fields["is_anonymous_topic"] = 1
        post.topic.save_custom_fields(true)
      end
    end
  end

  # --- PostSerializer overrides ---

  add_to_serializer(:post, :is_anonymous_post) do
    object.custom_fields["is_anonymous_post"].to_i
  end

  add_to_serializer(:post, :username) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin? && scope.user&.id != object.user_id
      "anonymous"
    else
      object.user&.username
    end
  end

  add_to_serializer(:post, :display_username) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin? && scope.user&.id != object.user_id
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :name) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin? && scope.user&.id != object.user_id
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :avatar_template) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin? && scope.user&.id != object.user_id
      AnonymousPostHelper.anonymous_user&.avatar_template || AnonymousPostHelper::ANON_AVATAR_FALLBACK
    else
      object.user&.avatar_template
    end
  end

  add_to_serializer(:post, :user_id) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin? && scope.user&.id != object.user_id
      AnonymousPostHelper.anonymous_user&.id
    else
      object.user_id
    end
  end

  # --- TopicViewSerializer: topic-level fields ---

  add_to_serializer(:topic_view, :is_anonymous_topic) do
    object.topic.custom_fields["is_anonymous_topic"].to_i
  end

  add_to_serializer(:topic_view, :user_id) do
    topic = object.topic
    if AnonymousPostHelper.anon_topic?(topic) && !scope.is_admin?
      nil
    else
      topic.user_id
    end
  end

  # --- TopicViewDetailsSerializer: created_by, last_poster, participants ---
  # Cannot use add_to_serializer(:topic_view_details, ...) — produces invalid constant name.
  # Use class_eval instead.

  TopicViewDetailsSerializer.class_eval do
    alias_method :original_created_by, :created_by
    def created_by
      topic = object.topic
      if AnonymousPostHelper.anon_topic?(topic) && !scope.is_admin?
        AnonymousPostHelper.anonymous_user_object
      else
        original_created_by
      end
    end

    alias_method :original_last_poster, :last_poster
    def last_poster
      topic = object.topic
      if !scope.is_admin?
        should_anonymize = false

        # Check if topic is anonymous and last poster is the OP
        if AnonymousPostHelper.anon_topic?(topic)
          last_poster_user = topic.last_poster
          should_anonymize = true if last_poster_user&.id == topic.user_id
        end

        # Check if the last post itself is anonymous (via direct DB query)
        last_post_id = topic.posts.order(post_number: :desc).limit(1).pluck(:id).first
        should_anonymize = true if last_post_id && AnonymousPostHelper.anon_post_by_id?(last_post_id)

        if should_anonymize
          return AnonymousPostHelper.anonymous_user_object
        end
      end

      original_last_poster
    end

    alias_method :original_participants, :participants
    def participants
      topic = object.topic
      return original_participants if scope.is_admin?

      # Get all user_ids with anonymous posts in this topic (single DB query)
      anon_user_ids = AnonymousPostHelper.anon_user_ids_in_topic(topic.id)

      return original_participants if anon_user_ids.empty?

      original_participants.map do |participant|
        # participants are Hashes: {user: <User>, post_count: N}
        user = participant.is_a?(Hash) ? participant[:user] : participant
        user_id = user.respond_to?(:id) ? user.id : nil

        if user_id && anon_user_ids.include?(user_id)
          # Check if ALL posts by this user are anonymous
          total_posts = topic.posts.where(user_id: user_id).count
          anon_posts = PostCustomField.where(name: "is_anonymous_post", value: "1")
            .joins("INNER JOIN posts ON posts.id = post_custom_fields.post_id")
            .where("posts.topic_id = ? AND posts.user_id = ?", topic.id, user_id)
            .count

          if total_posts == anon_posts
            if participant.is_a?(Hash)
              { user: AnonymousPostHelper.anonymous_user_object, post_count: participant[:post_count] }
            else
              obj = AnonymousPostHelper.anonymous_user_object
              obj.post_count = user.respond_to?(:post_count) ? user.post_count : 1
              obj
            end
          else
            participant
          end
        else
          participant
        end
      end
    end
  end

  # --- TopicListItemSerializer: posters in topic list ---

  add_to_serializer(:topic_list_item, :posters) do
    topic = object
    original_posters = topic.posters || []

    return original_posters if scope.is_admin?

    anon_user_ids = AnonymousPostHelper.anon_user_ids_in_topic(topic.id)
    return original_posters if anon_user_ids.empty?

    original_posters.map do |poster|
      if poster.user && anon_user_ids.include?(poster.user.id) && scope.user&.id != poster.user.id
        anon_poster = OpenStruct.new(
          user: AnonymousPostHelper.anonymous_user_object,
          description: poster.description,
          extras: poster.extras,
          primary_group: nil,
        )
        def anon_poster.read_attribute_for_serialization(attr)
          send(attr)
        end
        anon_poster
      else
        poster
      end
    end
  end

  # --- discourse-reactions: anonymize reaction users on anonymous posts ---

  if defined?(DiscourseReactions::ReactionUserSerializer)
    DiscourseReactions::ReactionUserSerializer.class_eval do
      alias_method :original_username, :username
      def username
        post = @options[:post] || object.try(:post)
        if post && AnonymousPostHelper.anon_post?(post) && !scope.is_admin?
          AnonymousPostHelper.anonymous_user&.username || "anonymous"
        else
          original_username
        end
      end

      alias_method :original_avatar_template, :avatar_template
      def avatar_template
        post = @options[:post] || object.try(:post)
        if post && AnonymousPostHelper.anon_post?(post) && !scope.is_admin?
          AnonymousPostHelper.anonymous_user&.avatar_template || AnonymousPostHelper::ANON_AVATAR_FALLBACK
        else
          original_avatar_template
        end
      end
    end
  end

  # --- PostRevisionSerializer: hide real editor for anonymous posts ---

  PostRevisionSerializer.class_eval do
    alias_method :original_username, :username
    def username
      if AnonymousPostHelper.anon_post_by_id?(object.post_id) && !scope.is_admin?
        AnonymousPostHelper.anonymous_user&.username || "anonymous"
      else
        original_username
      end
    end

    alias_method :original_display_username, :display_username
    def display_username
      if AnonymousPostHelper.anon_post_by_id?(object.post_id) && !scope.is_admin?
        AnonymousPostHelper.anonymous_user&.name || I18n.t("js.anonymous_post.anonymous_name")
      else
        original_display_username
      end
    end

    alias_method :original_avatar_template, :avatar_template
    def avatar_template
      if AnonymousPostHelper.anon_post_by_id?(object.post_id) && !scope.is_admin?
        AnonymousPostHelper.anonymous_user&.avatar_template || AnonymousPostHelper::ANON_AVATAR_FALLBACK
      else
        original_avatar_template
      end
    end
  end

  # --- PostAlerter: anonymize notifications for anonymous posts ---

  module ::AnonymousPostAlerterExtension
    def create_notification(user, notification_type, post, opts = {})
      if post && AnonymousPostHelper.anon_post?(post)
        anon = AnonymousPostHelper.anonymous_user
        if anon
          opts[:display_username] = anon.username
          opts[:acting_user_id] = anon.id
        else
          opts[:display_username] = "anonymous"
        end
      end
      super(user, notification_type, post, opts)
    end
  end

  PostAlerter.prepend(AnonymousPostAlerterExtension)

  # --- discourse-solved: anonymize "accepted solution" notifications ---

  on(:accepted_solution) do |post|
    if post && AnonymousPostHelper.anon_post_by_id?(post.id)
      anon = AnonymousPostHelper.anonymous_user
      # Fix notifications created in the last minute for this post
      Notification.where(
        topic_id: post.topic_id,
        post_number: post.post_number,
      ).where("created_at > ?", 1.minute.ago).each do |n|
        data = JSON.parse(n.data)
        data["display_username"] = anon&.username || "anonymous"
        data["username"] = anon&.username || "anonymous"
        n.update(data: data.to_json)
      end
    end
  end

  # --- UserSummary: hide anonymous posts/topics from profile summary ---

  module ::AnonymousUserSummaryExtension
    def top_replies
      results = super
      anon_post_ids = PostCustomField.where(name: "is_anonymous_post", value: "1").pluck(:post_id)
      results.reject { |r| anon_post_ids.include?(r.id) }
    end

    def top_topics
      results = super
      anon_topic_ids = TopicCustomField.where(name: "is_anonymous_topic", value: "1").pluck(:topic_id)
      results.reject { |t| anon_topic_ids.include?(t.id) }
    end

    def replies
      results = super
      anon_post_ids = PostCustomField.where(name: "is_anonymous_post", value: "1").pluck(:post_id)
      results.reject { |r| anon_post_ids.include?(r.id) }
    end

    def topics
      results = super
      anon_topic_ids = TopicCustomField.where(name: "is_anonymous_topic", value: "1").pluck(:topic_id)
      results.reject { |t| anon_topic_ids.include?(t.id) }
    end
  end

  UserSummary.prepend(AnonymousUserSummaryExtension)

  # --- UserAction: hide anonymous posts from other users' activity ---
  # Filter at the stream level by patching UserAction.stream

  UserAction.class_eval do
    class << self
      alias_method :original_stream, :stream

      def stream(opts = {})
        result = original_stream(opts)

        # If viewing someone else's activity (not self, not admin)
        guardian = opts[:guardian]
        acting_user_id = opts[:user_id]

        if guardian && !guardian.is_admin? && guardian.user&.id != acting_user_id
          result = result.reject do |action|
            if action.respond_to?(:post_id) && action.post_id.present?
              AnonymousPostHelper.anon_post_by_id?(action.post_id)
            else
              false
            end
          end
        end

        result
      end
    end
  end
end
