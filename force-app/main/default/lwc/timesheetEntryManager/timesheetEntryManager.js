import { LightningElement, track } from 'lwc';

export default class TimesheetEntryManager extends LightningElement {
    @track activeTab = 'upload';

    get uploadTabClass() {
        return this.activeTab === 'upload' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get entryTabClass() {
        return this.activeTab === 'entry' ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    get uploadContentClass() {
        return this.activeTab === 'upload' ? 'slds-tabs_default__content slds-show' : 'slds-tabs_default__content slds-hide';
    }

    get entryContentClass() {
        return this.activeTab === 'entry' ? 'slds-tabs_default__content slds-show' : 'slds-tabs_default__content slds-hide';
    }

    get uploadTabActive() {
        return this.activeTab === 'upload';
    }

    get entryTabActive() {
        return this.activeTab === 'entry';
    }

    handleTabSelect(event) {
        this.activeTab = event.target.dataset.tab;
    }
}