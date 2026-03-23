import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class AnonymousPostCheckbox extends Component {
  @service siteSettings;

  @tracked checked = false;

  get shouldRender() {
    if (!this.siteSettings.anonymous_post_enabled) {
      console.log("[ANON-POST] plugin disabled in site settings");
      return false;
    }

    const model = this.args.outletArgs?.model;
    if (!model) {
      console.log("[ANON-POST] no model in outletArgs");
      return false;
    }

    const action = model.action;
    const result = action === "reply" || action === "createTopic";
    console.log("[ANON-POST] shouldRender:", result, "action:", action);
    return result;
  }

  @action
  toggle() {
    this.checked = !this.checked;
    const model = this.args.outletArgs?.model;
    if (model) {
      model.set("is_anonymous_post", this.checked ? 1 : 0);
      console.log("[ANON-POST] toggled:", this.checked, "model.is_anonymous_post:", model.get("is_anonymous_post"));
    }
  }

  <template>
    {{#if this.shouldRender}}
      <div class="anonymous-post-checkbox">
        <label class="checkbox-label">
          <input
            type="checkbox"
            checked={{this.checked}}
            {{on "change" this.toggle}}
          />
          {{icon "ghost"}}
          {{i18n "anonymous_post.btn_label"}}
        </label>
      </div>
    {{/if}}
  </template>
}
