import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from "@ember/object";
import { inject as service } from "@ember/service"
import Group from "discourse/models/group";

export default class PrivateReplies extends Component {
    @service siteSettings;
    @tracked enabled_for_category = this.args.outletArgs.category.custom_fields.private_replies_enabled;

    constructor() {
        super(...arguments);
    }

    @action
    enable_for_category(event) {
        this.enabled_for_category = event.target.checked;
    }

    get category_private_replies_enabled() {
        return (this.siteSettings.private_replies_on_selected_categories_only == false) || (this.enabled_for_category);
    }
}