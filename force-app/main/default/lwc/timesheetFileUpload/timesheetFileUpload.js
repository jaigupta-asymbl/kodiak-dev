import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processTimesheetFile from '@salesforce/apex/TimesheetEntryController.processTimesheetFile';
import getFieldMappings from '@salesforce/apex/TimesheetEntryController.getFieldMappings';

export default class TimesheetFileUpload extends LightningElement {
    @track selectedClient = '';
    @track uploadedFiles = [];
    @track isProcessing = false;
    @track mappings = [];
    @track clientOptions = [];

    acceptedFormats = ['.csv', '.xlsx', '.xls'];

    @wire(getFieldMappings)
    wiredMappings({ error, data }) {
        if (data) {
            this.mappings = data;
            // Extract unique client names for dropdown
            const clients = new Set();
            data.forEach(mapping => {
                if (mapping.Client_Name__c) {
                    clients.add(mapping.Client_Name__c);
                }
            });
            this.clientOptions = Array.from(clients).map(client => ({
                label: client,
                value: client
            }));
            this.clientOptions.unshift({ label: 'Select Client', value: '' });
        } else if (error) {
            this.showToast('Error', 'Failed to load field mappings', 'error');
        }
    }

    handleClientChange(event) {
        this.selectedClient = event.detail.value;
    }

    handleUploadFinished(event) {
        this.uploadedFiles = event.detail.files;
        this.showToast('Success', 'File uploaded successfully', 'success');
    }

    async handleProcessFile() {
        if (!this.selectedClient) {
            this.showToast('Error', 'Please select a client', 'error');
            return;
        }

        if (this.uploadedFiles.length === 0) {
            this.showToast('Error', 'Please upload a file first', 'error');
            return;
        }

        this.isProcessing = true;
        try {
            const file = this.uploadedFiles[0];
            const result = await processTimesheetFile({
                contentVersionId: file.documentId,
                clientName: this.selectedClient
            });

            if (result.success) {
                this.showToast('Success', `Successfully processed ${result.recordsCreated} records`, 'success');
                this.resetForm();
            } else {
                this.showToast('Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to process file: ' + error.body.message, 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    resetForm() {
        this.selectedClient = '';
        this.uploadedFiles = [];
        // Reset file upload component
        const fileUpload = this.template.querySelector('lightning-file-upload');
        if (fileUpload) {
            fileUpload.files = [];
        }
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