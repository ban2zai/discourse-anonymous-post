import { apiInitializer } from "discourse/lib/api";
import { iconHTML } from "discourse/lib/icon-library";
import AnonymousPostCheckbox from "../components/anonymous-post-checkbox";

export default apiInitializer("0.4.0", (api) => {
  api.serializeOnCreate("is_anonymous_post");
  api.addTrackedPostProperties("is_anonymous_post");

  api.renderInOutlet("composer-after-save-or-cancel", AnonymousPostCheckbox);

  api.addPostClassesCallback((attrs) => {
    return attrs.is_anonymous_post ? ["is-anonymous-post"] : [];
  });

  api.addPosterIcons((cfs, attrs) => {
    if (attrs.is_anonymous_post) {
      return [{ icon: "ghost", className: "anon-post-indicator" }];
    }
    return [];
  });

  // Ghost icon left of topic title in topic list for anonymous topics
  api.decorateTopicTitle((topic, node, topicTitleType) => {
    if (topic.is_anonymous_topic && topicTitleType !== "topic-title") {
      const parent = node.parentElement;
      if (parent && !parent.querySelector(".anon-topic-icon")) {
        const icon = document.createElement("span");
        icon.className = "anon-topic-icon";
        icon.innerHTML = iconHTML("ghost");
        parent.insertBefore(icon, node);
      }
    }
  });
});
