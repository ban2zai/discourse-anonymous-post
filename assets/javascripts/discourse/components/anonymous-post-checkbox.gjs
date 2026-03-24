import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class AnonymousPostCheckbox extends Component {
  @service siteSettings;
  @service currentUser;

  @tracked checked = false;
  _initialized = false;

  get shouldRender() {
    if (!this.siteSettings.anonymous_post_enabled) {
      return false;
    }

    const model = this.args.outletArgs?.model;
    if (!model) {
      return false;
    }

    const modelAction = model.action;
    const result = modelAction === "reply" || modelAction === "createTopic";

    // Auto-check when replying in own anonymous topic
    if (result && modelAction === "reply" && !this._initialized) {
      const topic = model.topic;
      if (
        topic?.is_anonymous_topic &&
        this.currentUser &&
        topic.user_id === this.currentUser.id
      ) {
        this._initialized = true;
        this.checked = true;
        model.set("is_anonymous_post", 1);
      }
    }

    return result;
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
