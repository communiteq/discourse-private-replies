import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from "@ember/object";
import { inject as service } from "@ember/service"
import Group from "discourse/models/group";

export default class PrivateReplies extends Component {
    @service siteSettings;

    constructor() {
        super(...arguments);
    }
}