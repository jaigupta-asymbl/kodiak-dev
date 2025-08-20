import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFinalizedInvoices from '@salesforce/apex/InvoiceCSVExportService.getFinalizedInvoices';
import exportInvoicesToCSV from '@salesforce/apex/InvoiceCSVExportService.exportInvoicesToCSV';

const columns = [
    { label: 'Invoice Name', fieldName: 'Name', type: 'text', sortable: true },
    { label: 'Account', fieldName: 'AccountName', type: 'text', sortable: true },
    { label: 'Invoice Date', fieldName: 'Invoice_Date__c', type: 'date', sortable: true },
    { label: 'Total Amount', fieldName: 'Total_Amount__c', type: 'currency', sortable: true },
    { label: 'Status', fieldName: 'Status__c', type: 'text', sortable: true }
];

export default class InvoiceCSVExport extends LightningElement {
    @track invoices = [];
    @track selectedInvoices = [];
    @track isLoading = false;
    @track isExporting = false;
    @track error;
    
    columns = columns;
    
    @wire(getFinalizedInvoices)
    wiredInvoices({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.invoices = data.map(invoice => ({
                ...invoice,
                AccountName: invoice.Account__r ? invoice.Account__r.Name : ''
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Error loading invoices';
            this.invoices = [];
            this.showToast('Error', this.error, 'error');
        }
    }
    
    connectedCallback() {
        this.isLoading = true;
    }
    
    handleRowSelection(event) {
        this.selectedInvoices = event.detail.selectedRows.map(row => row.Id);
    }
    
    handleRefresh() {
        this.isLoading = true;
        this.selectedInvoices = [];
        // Clear the datatable selection
        const datatable = this.template.querySelector('lightning-datatable');
        if (datatable) {
            datatable.selectedRows = [];
        }
        // Refresh the wire service
        eval("$A.get('e.force:refreshView').fire();");
    }
    
    async handleExport() {
        if (this.selectedInvoices.length === 0) {
            this.showToast('Warning', 'Please select at least one invoice to export', 'warning');
            return;
        }
        
        this.isExporting = true;
        
        try {
            const result = await exportInvoicesToCSV({ invoiceIds: this.selectedInvoices });
            
            if (result.success) {
                // Create and download CSV file
                this.downloadCSV(result.csvContent, result.fileName);
                
                // Show success message
                this.showToast('Success', result.message, 'success');
                
                // Refresh the invoice list
                this.handleRefresh();
                
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Export failed: ' + error.body?.message || error.message, 'error');
        } finally {
            this.isExporting = false;
        }
    }
    
    downloadCSV(csvContent, fileName) {
        try {
            // Create blob and download
            const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
            
            // Create download link
            const link = document.createElement('a');
            if (link.download !== undefined) {
                const url = URL.createObjectURL(blob);
                link.setAttribute('href', url);
                link.setAttribute('download', fileName);
                link.style.visibility = 'hidden';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                URL.revokeObjectURL(url);
            }
        } catch (error) {
            this.showToast('Error', 'Failed to download CSV file', 'error');
        }
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }
    
    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }
    
    get hasSelectedInvoices() {
        return this.selectedInvoices.length > 0;
    }
    
    get selectedCount() {
        return this.selectedInvoices.length;
    }
    
    get totalCount() {
        return this.invoices.length;
    }
    
    get exportButtonDisabled() {
        return this.isExporting || this.selectedInvoices.length === 0;
    }
    
    get refreshButtonDisabled() {
        return this.isLoading || this.isExporting;
    }
    
    get exportButtonLabel() {
        if (this.isExporting) {
            return 'Exporting...';
        }
        return this.selectedCount > 0 ? `Export ${this.selectedCount} Invoices` : 'Export to CSV';
    }
    
    get statusMessage() {
        return `Status: Showing Finalized invoices only`;
    }
    
    get selectionMessage() {
        if (this.selectedCount === 0) {
            return 'No invoices selected';
        }
        return `${this.selectedCount} of ${this.totalCount} selected`;
    }
    
    get statusBadge() {
        return `Total: ${this.totalCount}`;
    }
}