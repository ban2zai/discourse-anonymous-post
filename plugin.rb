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
    ANON_AVATAR = "/letter_avatar_proxy/v4/letter/a/b3b5b3/{size}.png"

    def self.anonymous_user_hash
      {
        id: -1,
        username: "anonymous",
        name: I18n.t("js.anonymous_post.anonymous_name"),
        avatar_template: ANON_AVATAR,
      }
    end

    # Returns a serializer-compatible object (BasicUserSerializer needs read_attribute_for_serialization)
    def self.anonymous_user_object
      obj = OpenStruct.new(
        id: -1,
        username: "anonymous",
        name: I18n.t("js.anonymous_post.anonymous_name"),
        avatar_template: ANON_AVATAR,
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
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin?
      "anonymous"
    else
      object.user&.username
    end
  end

  add_to_serializer(:post, :display_username) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin?
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :name) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin?
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :avatar_template) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin?
      AnonymousPostHelper::ANON_AVATAR
    else
      object.user&.avatar_template
    end
  end

  add_to_serializer(:post, :user_id) do
    if AnonymousPostHelper.anon_post?(object) && !scope.is_admin?
      nil
    else
      object.user_id
    end
  end

  # --- TopicViewSerializer: topic-level user_id ---

  add_to_serializer(:topic_view, :user_id) do
    topic = object.topic
    if AnonymousPostHelper.anon_topic?(topic) && !scope.is_admin?
      Rails.logger.warn("[ANON-POST] TopicViewSerializer: hiding user_id for topic #{topic.id}")
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
        Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing created_by for topic #{topic.id}")
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
          Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing last_poster for topic #{topic.id}")
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
        user_id = participant.respond_to?(:id) ? participant.id : nil

        if user_id && anon_user_ids.include?(user_id)
          # Check if ALL posts by this user are anonymous
          total_posts = topic.posts.where(user_id: user_id).count
          anon_posts = PostCustomField.where(name: "is_anonymous_post", value: "1")
            .joins("INNER JOIN posts ON posts.id = post_custom_fields.post_id")
            .where("posts.topic_id = ? AND posts.user_id = ?", topic.id, user_id)
            .count

          if total_posts == anon_posts
            Rails.logger.warn("[ANON-POST] TopicViewDetailsSerializer: anonymizing participant #{user_id} in topic #{topic.id}")
            obj = AnonymousPostHelper.anonymous_user_object
            obj.post_count = participant.respond_to?(:post_count) ? participant.post_count : 1
            obj
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

    if AnonymousPostHelper.anon_topic?(topic) && !scope.is_admin?
      Rails.logger.warn("[ANON-POST] TopicListItemSerializer: anonymizing posters for topic #{topic.id}")

      original_posters.map do |poster|
        if poster.description&.include?("Original Poster")
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
    else
      original_posters
    end
  end

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
