import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processTimesheetFile from '@salesforce/apex/TimesheetEntryController.processTimesheetFile';

export default class TimesheetFileUpload extends LightningElement {
    @track uploadedFiles = [];
    @track isProcessing = false;

    acceptedFormats = ['.csv', '.xlsx', '.xls'];

    handleUploadFinished(event) {
        this.uploadedFiles = event.detail.files;
        this.showToast('Success', 'File uploaded successfully', 'success');
    }

    async handleProcessFile() {
        if (this.uploadedFiles.length === 0) {
            this.showToast('Error', 'Please upload a file first', 'error');
            return;
        }

        this.isProcessing = true;
        try {
            const file = this.uploadedFiles[0];
            const result = await processTimesheetFile({
                contentVersionId: file.documentId
            });

            if (result.success) {
                this.showToast('Success', `Successfully processed ${result.recordsCreated} records. ${result.errorMessage}`, 'success');
                this.resetForm();
            } else {
                this.showToast('Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to process file: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    resetForm() {
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