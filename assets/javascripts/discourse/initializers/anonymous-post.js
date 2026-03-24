import { apiInitializer } from "discourse/lib/api";
import AnonymousPostCheckbox from "../components/anonymous-post-checkbox";

export default apiInitializer("0.3.0", (api) => {
  api.serializeOnCreate("is_anonymous_post");
  api.addTrackedPostProperties("is_anonymous_post");

  api.renderInOutlet("composer-fields-below", AnonymousPostCheckbox);

  api.includePostAttributes("is_anonymous_post");

  api.addPostClassesCallback((attrs) => {
    return attrs.is_anonymous_post ? ["is-anonymous-post"] : [];
  });

  api.decorateWidget("poster-name:after", (helper) => {
    const attrs = helper.attrs;
    if (attrs && attrs.is_anonymous_post) {
      return helper.h("span.anon-post-indicator", [
        helper.iconNode("ghost"),
      ]);
    }
  });
});
