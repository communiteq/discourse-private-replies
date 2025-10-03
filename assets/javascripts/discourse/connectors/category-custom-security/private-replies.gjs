import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { Input } from "@ember/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

export default class PrivateReplies extends Component {
    @service siteSettings;

    @tracked
    enabled_for_category = this.args.outletArgs.category.custom_fields.private_replies_enabled;

    constructor() {
        super(...arguments);
    }

    @action
    enable_for_category(event) {
        this.enabled_for_category = event.target.checked;
    }

    get category_private_replies_enabled() {
        return (this.siteSettings.private_replies_on_selected_categories_only === false) || (this.enabled_for_category);
    }

<template>{{#if this.siteSettings.private_replies_enabled}}
  <section>
    <h3>{{i18n "private_replies.title"}}</h3>
  </section>
  {{#if this.siteSettings.private_replies_on_selected_categories_only}}
    <section class="field category_private_replies_enabled">
        <label>
        <Input @type="checkbox" @checked={{this.args.outletArgs.category.custom_fields.private_replies_enabled}} {{on "change" this.enable_for_category}} />
        {{i18n "private_replies.private_replies_enabled"}}
        </label>
    </section>
  {{/if}}
  {{#if this.category_private_replies_enabled}}
    <section class="field category_private_replies_default_enabled">
        <label>
        <Input @type="checkbox" @checked={{this.args.outletArgs.category.custom_fields.private_replies_default_enabled}} />
        {{i18n "private_replies.category_default_enabled"}}
        </label>
        <span>{{i18n "private_replies.category_default_subtext"}}</span>
    </section>
  {{/if}}
{{/if}}</template>}