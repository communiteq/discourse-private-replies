
import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function registerTopicFooterButtons(api, container, siteSettings) {
  api.registerTopicFooterButton({
    id: "privatereplies",
    icon() {
      const isPrivate = this.get("topic.private_replies");
      return isPrivate ? "far-eye" : "far-eye-slash";
    },
    priority: 250,
    title() {
      const isPrivate = this.get("topic.private_replies");
      return `private_replies.button.${isPrivate ? "public_replies" : "private_replies"}.help`;
    },
    label() {
      const isPrivate = this.get("topic.private_replies");
      return `private_replies.button.${isPrivate ? "public_replies" : "private_replies"}.button`;
    },
    action() {
      if (!this.get("topic.user_id")) {
        return;
      }

      var action;
      if (this.get("topic.private_replies")) {
        action = 'disable';
      } else {
        action = 'enable';
      }

      return ajax('/private_replies/' + action + '.json', {
        type: "PUT",
        data: { topic_id: this.get("topic.id") }
      })
      .then(result => {
        this.set("topic.private_replies", result.private_replies_enabled);
      })
      .catch(popupAjaxError);
    },
    dropdown() {
      return this.site.mobileView;
    },
    classNames: ["private-replies"],
    dependentKeys: [
      "topic.private_replies"
    ],
    displayed() {
      const topic_owner_id = this.get("topic.user_id");
      var topic = this.get("topic");
      if ((siteSettings.private_replies_on_selected_categories_only == false) || (topic?.category?.custom_fields.private_replies_enabled)) {
        return this.currentUser && ((this.currentUser.id == topic_owner_id) || this.currentUser.staff);
      }
      return false;
    }
  });
}

export default {
  name: "extend-for-privatereplies",
  initialize(container) {
    const siteSettings = container.lookup("site-settings:main");
    if (!siteSettings.private_replies_enabled) {
      return;
    }

    withPluginApi("0.8.28", api => registerTopicFooterButtons(api, container, siteSettings));
  }
};
