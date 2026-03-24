import { apiInitializer } from "discourse/lib/api";
import AnonymousPostCheckbox from "../components/anonymous-post-checkbox";

export default apiInitializer("0.3.0", (api) => {
  api.serializeOnCreate("is_anonymous_post");
  api.addTrackedPostProperties("is_anonymous_post");

  api.renderInOutlet("composer-fields-below", AnonymousPostCheckbox);

  api.addPostClassesCallback((attrs) => {
    return attrs.is_anonymous_post ? ["is-anonymous-post"] : [];
  });

  api.addPosterIcons((cfs, attrs) => {
    if (attrs.is_anonymous_post) {
      return [{ icon: "ghost", className: "anon-post-indicator" }];
    }
    return [];
  });
});
