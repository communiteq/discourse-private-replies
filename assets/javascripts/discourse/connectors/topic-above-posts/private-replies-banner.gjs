import Component from '@glimmer/component';
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class PrivateRepliesBanner extends Component {
  @service siteSettings;

  get hasPrivateReplies() {
    return this.args.outletArgs.model.get("private_replies");
  }

  get isUserViewLimited() {
    return this.hasPrivateReplies && this.args.outletArgs.model.get("private_replies_limited");
  }

  get whoCanSee() {
    return i18n("private_replies.topic_banner_line_2", {
      group: this.siteSettings.private_replies_topic_starter_primary_group_can_see_all ? i18n("private_replies.topic_banner_line_2_group") : "",
      participants: this.siteSettings.private_replies_participants_can_see_all ? i18n("private_replies.topic_banner_line_2_participants") : ""
    });
  }

  <template>
    {{#if this.hasPrivateReplies}}
      <div class="row">
        <div class="post-notice custom">
          {{icon 'user-secret'}}
          <div>
            <p>
              {{#if this.isUserViewLimited}}
                {{i18n 'private_replies.topic_banner_line_1'}}
              {{else}}
                {{i18n 'private_replies.topic_banner_line_1_all'}}
              {{/if}}
              <br>
              {{ this.whoCanSee }}
            </p>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
