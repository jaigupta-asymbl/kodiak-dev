import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactsWithPlacements from '@salesforce/apex/TimesheetEntryController.getContactsWithPlacements';
import getPlacementsForContact from '@salesforce/apex/TimesheetEntryController.getPlacementsForContact';
import getBillingProfileLabels from '@salesforce/apex/TimesheetEntryController.getBillingProfileLabels';
import saveTimesheetData from '@salesforce/apex/TimesheetEntryController.saveTimesheetData';

export default class TimesheetManualEntry extends LightningElement {
    @track selectedContactId = '';
    @track selectedPlacementId = '';
    @track contactOptions = [];
    @track placementOptions = [];
    @track timeEntries = [];
    @track customFieldLabels = {};
    @track isLoading = false;
    @track isSaving = false;

    get isPlacementDisabled() {
        return !this.selectedContactId;
    }

    get isAddRowDisabled() {
        return !this.selectedPlacementId;
    }

    get customFieldNames() {
        return ['customField1', 'customField2', 'customField3', 'customField4', 'customField5'];
    }

    // Initialize with 5 empty rows
    connectedCallback() {
        this.initializeTimeEntries();
    }

    @wire(getContactsWithPlacements)
    wiredContacts({ error, data }) {
        if (data) {
            this.contactOptions = [
                { label: 'Select Contact', value: '' },
                ...data.map(contact => ({
                    label: contact.Name,
                    value: contact.Id
                }))
            ];
        } else if (error) {
            this.showToast('Error', 'Failed to load contacts', 'error');
        }
    }

    initializeTimeEntries() {
        this.timeEntries = Array(5).fill(null).map((_, index) => ({
            id: `new-${index}`,
            date: '',
            regularHours: 0,
            overtimeHours: 0,
            doubleTimeHours: 0,
            sickHours: 0,
            ptoHours: 0,
            holidayHours: 0,
            customField1: '',
            customField2: '',
            customField3: '',
            customField4: '',
            customField5: '',
            customField1Key: `customField1-${index}`,
            customField2Key: `customField2-${index}`,
            customField3Key: `customField3-${index}`,
            customField4Key: `customField4-${index}`,
            customField5Key: `customField5-${index}`,
            isEditing: false,
            isNew: true
        }));
    }

    async handleContactChange(event) {
        this.selectedContactId = event.detail.value;
        this.selectedPlacementId = '';
        this.placementOptions = [];
        this.customFieldLabels = {};

        if (this.selectedContactId) {
            this.isLoading = true;
            try {
                const placements = await getPlacementsForContact({ contactId: this.selectedContactId });
                this.placementOptions = [
                    { label: 'Select Placement', value: '' },
                    ...placements.map(placement => ({
                        label: `${placement.Name} - ${placement.bpats__Account__r?.Name || 'No Client'}`,
                        value: placement.Id
                    }))
                ];
            } catch (error) {
                this.showToast('Error', 'Failed to load placements', 'error');
            } finally {
                this.isLoading = false;
            }
        }
    }

    async handlePlacementChange(event) {
        this.selectedPlacementId = event.detail.value;
        
        if (this.selectedPlacementId) {
            this.isLoading = true;
            try {
                const labels = await getBillingProfileLabels({ placementId: this.selectedPlacementId });
                this.customFieldLabels = labels || {};
            } catch (error) {
                this.showToast('Error', 'Failed to load custom field labels', 'error');
            } finally {
                this.isLoading = false;
            }
        }
    }

    handleFieldChange(event) {
        const rowId = event.target.dataset.rowId;
        const fieldName = event.target.dataset.field;
        const value = event.target.value;

        this.timeEntries = this.timeEntries.map(entry => {
            if (entry.id === rowId) {
                return { ...entry, [fieldName]: value };
            }
            return entry;
        });
    }

    handleEdit(event) {
        const rowId = event.target.dataset.rowId;
        this.timeEntries = this.timeEntries.map(entry => {
            if (entry.id === rowId) {
                return { ...entry, isEditing: true };
            }
            return entry;
        });
    }

    handleSaveRow(event) {
        const rowId = event.target.dataset.rowId;
        this.timeEntries = this.timeEntries.map(entry => {
            if (entry.id === rowId) {
                return { ...entry, isEditing: false };
            }
            return entry;
        });
    }

    handleDeleteRow(event) {
        const rowId = event.target.dataset.rowId;
        this.timeEntries = this.timeEntries.filter(entry => entry.id !== rowId);
    }

    handleAddRow() {
        const newRow = {
            id: `new-${Date.now()}`,
            date: '',
            regularHours: 0,
            overtimeHours: 0,
            doubleTimeHours: 0,
            sickHours: 0,
            ptoHours: 0,
            holidayHours: 0,
            customField1: '',
            customField2: '',
            customField3: '',
            customField4: '',
            customField5: '',
            isEditing: true,
            isNew: true
        };
        this.timeEntries = [...this.timeEntries, newRow];
    }

    async handleSaveAll() {
        if (!this.selectedContactId || !this.selectedPlacementId) {
            this.showToast('Error', 'Please select contact and placement', 'error');
            return;
        }

        // Filter out empty rows
        const validEntries = this.timeEntries.filter(entry => 
            entry.date && (
                entry.regularHours > 0 || 
                entry.overtimeHours > 0 || 
                entry.doubleTimeHours > 0 ||
                entry.sickHours > 0 ||
                entry.ptoHours > 0 ||
                entry.holidayHours > 0
            )
        );

        if (validEntries.length === 0) {
            this.showToast('Error', 'Please enter at least one time entry with hours', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const result = await saveTimesheetData({
                contactId: this.selectedContactId,
                placementId: this.selectedPlacementId,
                timeEntries: validEntries
            });

            if (result.success) {
                this.showToast('Success', 'Timesheet data saved successfully', 'success');
                this.initializeTimeEntries(); // Reset form
            } else {
                this.showToast('Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to save timesheet data: ' + error.body.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Getter methods for custom field labels
    get customField1Label() {
        return this.customFieldLabels.customField1 || 'Custom Field 1';
    }

    get customField2Label() {
        return this.customFieldLabels.customField2 || 'Custom Field 2';
    }

    get customField3Label() {
        return this.customFieldLabels.customField3 || 'Custom Field 3';
    }

    get customField4Label() {
        return this.customFieldLabels.customField4 || 'Custom Field 4';
    }

    get customField5Label() {
        return this.customFieldLabels.customField5 || 'Custom Field 5';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}