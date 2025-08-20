public class TimesheetInvoiceGenerationBatch implements Queueable {
    
    private List<Id> timesheetIds;
    
    public TimesheetInvoiceGenerationBatch(List<Id> timesheetIds) {
        this.timesheetIds = timesheetIds;
    }
    
    public void execute(QueueableContext context) {
        try {
            InvoiceGenerationService.InvoiceResult result = 
                InvoiceGenerationService.processTimesheetsForInvoicing(timesheetIds);
            
            // Log the result
            if (result.success) {
                System.debug('Invoice generation successful. Invoices created: ' + 
                           result.invoicesCreated + ', updated: ' + result.invoicesUpdated);
                
                // Update timesheets to mark them as processed
                updateTimesheetInvoiceStatus(timesheetIds, true, null);
            } else {
                System.debug('Invoice generation failed: ' + result.errorMessage);
                
                // Update timesheets with error status
                updateTimesheetInvoiceStatus(timesheetIds, false, result.errorMessage);
            }
            
        } catch (Exception e) {
            System.debug('Unexpected error in invoice generation: ' + e.getMessage());
            updateTimesheetInvoiceStatus(timesheetIds, false, e.getMessage());
        }
    }
    
    /**
     * Static method to enqueue the batch processing
     */
    public static void processTimesheets(List<Id> timesheetIds) {
        if (!timesheetIds.isEmpty()) {
            System.enqueueJob(new TimesheetInvoiceGenerationBatch(timesheetIds));
        }
    }
    
    /**
     * Update timesheet records with invoice processing status
     */
    private void updateTimesheetInvoiceStatus(List<Id> timesheetIds, Boolean success, String errorMessage) {
        List<ASYMBL_Time__Timesheet__c> timesheetsToUpdate = new List<ASYMBL_Time__Timesheet__c>();
        
        for (Id tsId : timesheetIds) {
            ASYMBL_Time__Timesheet__c ts = new ASYMBL_Time__Timesheet__c();
            ts.Id = tsId;
            
            if (success) {
                ts.Invoice_Generation_Status__c = 'Completed';
                ts.Invoice_Generation_Error__c = null;
            } else {
                ts.Invoice_Generation_Status__c = 'Failed';
                ts.Invoice_Generation_Error__c = errorMessage;
            }
            
            timesheetsToUpdate.add(ts);
        }
        
        try {
            update timesheetsToUpdate;
        } catch (Exception e) {
            System.debug('Error updating timesheet invoice status: ' + e.getMessage());
        }
    }
}