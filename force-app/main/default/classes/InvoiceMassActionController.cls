public class InvoiceMassActionController {
    
    public class MassActionResult {
        public Boolean success;
        public String message;
        public Integer totalInvoices;
        public Integer accountGroups;
        public List<String> warnings;
        
        public MassActionResult() {
            this.success = true;
            this.warnings = new List<String>();
        }
    }
    
    @AuraEnabled
    public static MassActionResult sendInvoiceEmails(List<Id> invoiceIds) {
        MassActionResult result = new MassActionResult();
        result.totalInvoices = invoiceIds.size();
        
        try {
            if (invoiceIds.isEmpty()) {
                result.success = false;
                result.message = 'No invoices selected';
                return result;
            }
            
            validateInvoiceSelection(invoiceIds, result);
            
            if (result.success) {
                InvoiceEmailService.EmailResult emailResult = InvoiceEmailService.sendInvoicesByAccount(invoiceIds);
                
                if (emailResult.success) {
                    result.accountGroups = emailResult.emailsSent;
                    result.message = 'Successfully sent ' + result.totalInvoices + ' invoices in ' + result.accountGroups + ' email(s)';
                } else {
                    result.success = false;
                    result.message = emailResult.error;
                    if (!emailResult.failedInvoices.isEmpty()) {
                        result.message += '. Failed invoices: ' + String.join(emailResult.failedInvoices, ', ');
                    }
                }
            }
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error processing invoices: ' + e.getMessage();
        }
        
        return result;
    }
    
    @AuraEnabled
    public static MassActionResult generateInvoicePDFs(List<Id> invoiceIds) {
        MassActionResult result = new MassActionResult();
        result.totalInvoices = invoiceIds.size();
        
        try {
            if (invoiceIds.isEmpty()) {
                result.success = false;
                result.message = 'No invoices selected';
                return result;
            }
            
            List<String> failedPDFs = new List<String>();
            Integer successfulPDFs = 0;
            
            for (Id invoiceId : invoiceIds) {
                InvoicePDFGenerationService.InvoicePDFResult pdfResult = InvoicePDFGenerationService.generateInvoicePDF(invoiceId);
                
                if (pdfResult.success) {
                    successfulPDFs++;
                } else {
                    failedPDFs.add('Invoice ID: ' + invoiceId + ' - ' + pdfResult.error);
                }
            }
            
            if (failedPDFs.isEmpty()) {
                result.message = 'Successfully generated ' + successfulPDFs + ' PDF(s)';
            } else {
                result.success = false;
                result.message = 'Generated ' + successfulPDFs + ' PDFs, but ' + failedPDFs.size() + ' failed. Errors: ' + String.join(failedPDFs, '; ');
            }
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error generating PDFs: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static void validateInvoiceSelection(List<Id> invoiceIds, MassActionResult result) {
        List<Invoice__c> invoices = [
            SELECT Id, Name, Account__c, Account__r.Name, 
                   Billing_Profile__c, Billing_Profile__r.Name,
                   Billing_Profile__r.Billing_Contact__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];
        
        Set<Id> accounts = new Set<Id>();
        Set<Id> billingProfiles = new Set<Id>();
        List<String> invalidInvoices = new List<String>();
        
        for (Invoice__c invoice : invoices) {
            if (invoice.Account__c == null) {
                invalidInvoices.add(invoice.Name + ' (No Account)');
            } else {
                accounts.add(invoice.Account__c);
            }
            
            if (invoice.Billing_Profile__c == null) {
                invalidInvoices.add(invoice.Name + ' (No Billing Profile)');
            } else if (invoice.Billing_Profile__r.Billing_Contact__c == null) {
                invalidInvoices.add(invoice.Name + ' (No Billing Contact)');
            } else {
                billingProfiles.add(invoice.Billing_Profile__c);
            }
        }
        
        if (!invalidInvoices.isEmpty()) {
            result.success = false;
            result.message = 'Invalid invoices found: ' + String.join(invalidInvoices, ', ');
            return;
        }
        
        if (accounts.size() > 5) {
            result.warnings.add('Selected invoices span ' + accounts.size() + ' accounts - emails will be sent separately per account');
        }
        
        if (billingProfiles.size() > 1) {
            result.warnings.add('Multiple billing profiles detected - please verify recipient settings');
        }
        
        result.accountGroups = accounts.size();
    }
    
    @AuraEnabled
    public static List<Invoice__c> getInvoicePreview(List<Id> invoiceIds) {
        return [
            SELECT Id, Name, Invoice_Date__c,
                   Total_Amount__c, Account__c, Account__r.Name,
                   Billing_Profile__c, Billing_Profile__r.Name,
                   Billing_Profile__r.Billing_Contact__c, Billing_Profile__r.Billing_Contact__r.Email
            FROM Invoice__c
            WHERE Id IN :invoiceIds
            ORDER BY Account__r.Name, Name
        ];
    }
}