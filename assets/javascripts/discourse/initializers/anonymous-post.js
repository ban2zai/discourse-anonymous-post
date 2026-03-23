import { apiInitializer } from "discourse/lib/api";
import AnonymousPostCheckbox from "../components/anonymous-post-checkbox";

export default apiInitializer("0.3.0", (api) => {
  console.log("[ANON-POST] initializer loaded");

  api.serializeOnCreate("is_anonymous_post");
  api.addTrackedPostProperties("is_anonymous_post");

  api.renderInOutlet("composer-fields-below", AnonymousPostCheckbox);
});
