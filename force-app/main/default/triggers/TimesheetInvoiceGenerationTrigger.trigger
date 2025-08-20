trigger TimesheetInvoiceGenerationTrigger on ASYMBL_Time__Timesheet__c (after update) {
    
    // Collect timesheet IDs that need invoice generation
    List<Id> timesheetsToProcess = new List<Id>();
    
    for (ASYMBL_Time__Timesheet__c ts : Trigger.new) {
        ASYMBL_Time__Timesheet__c oldTs = Trigger.oldMap.get(ts.Id);
        
        // Check if Create Invoice checkbox was changed to true
        if (ts.Create_Invoice__c == true && 
            (oldTs.Create_Invoice__c != ts.Create_Invoice__c || 
             oldTs.ASYMBL_Time__Status__c != ts.ASYMBL_Time__Status__c)) {
            
            // Only process if status is Approved
            if (ts.ASYMBL_Time__Status__c == 'Approved') {
                timesheetsToProcess.add(ts.Id);
            }
        }
    }
    
    // Process invoice generation asynchronously to avoid governor limits
    if (!timesheetsToProcess.isEmpty()) {
        TimesheetInvoiceGenerationBatch.processTimesheets(timesheetsToProcess);
    }
}