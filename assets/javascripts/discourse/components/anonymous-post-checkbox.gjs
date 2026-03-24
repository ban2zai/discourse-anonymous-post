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
      return false;
    }

    const model = this.args.outletArgs?.model;
    if (!model) {
      return false;
    }

    const action = model.action;
    return action === "reply" || action === "createTopic";
  }

  @action
  toggle() {
    this.checked = !this.checked;
    const model = this.args.outletArgs?.model;
    if (model) {
      model.set("is_anonymous_post", this.checked ? 1 : 0);
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
