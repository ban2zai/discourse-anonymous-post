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

  on(:post_created) do |post, opts|
    value = opts[:is_anonymous_post].to_i
    if value.positive?
      post.custom_fields["is_anonymous_post"] = value
      post.save_custom_fields(true)
    end
  end

  add_to_serializer(:post, :is_anonymous_post) do
    object.custom_fields["is_anonymous_post"].to_i
  end

  add_to_serializer(:post, :username) do
    if object.custom_fields["is_anonymous_post"].to_i == 1 && !scope.is_admin?
      "anonymous"
    else
      object.user&.username
    end
  end

  add_to_serializer(:post, :name) do
    if object.custom_fields["is_anonymous_post"].to_i == 1 && !scope.is_admin?
      I18n.t("js.anonymous_post.anonymous_name")
    else
      object.user&.name
    end
  end

  add_to_serializer(:post, :avatar_template) do
    if object.custom_fields["is_anonymous_post"].to_i == 1 && !scope.is_admin?
      "/letter_avatar_proxy/v4/letter/a/b3b5b3/{size}.png"
    else
      object.user&.avatar_template
    end
  end

  add_to_serializer(:post, :user_id) do
    if object.custom_fields["is_anonymous_post"].to_i == 1 && !scope.is_admin?
      nil
    else
      object.user_id
    end
  end
end
