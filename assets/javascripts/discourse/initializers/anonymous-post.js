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
  api.onPageChange(() => {
    document.querySelectorAll("tr.topic-list-item[data-topic-id]").forEach((row) => {
      if (row.querySelector(".anon-topic-icon")) return;
      const topicId = parseInt(row.dataset.topicId, 10);
      const store = api.container.lookup("service:store");
      const topic = store.peekRecord("topic", topicId);
      if (topic && topic.is_anonymous_topic) {
        const titleLink = row.querySelector(".link-top-line a.title");
        if (titleLink) {
          const icon = document.createElement("span");
          icon.className = "anon-topic-icon";
          icon.innerHTML = iconHTML("ghost");
          titleLink.parentElement.insertBefore(icon, titleLink);
        }
      }
    });
  });
});
