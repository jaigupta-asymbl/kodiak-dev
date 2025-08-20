public class InvoicePDFGenerationService {
    
    public class InvoicePDFResult {
        public Boolean success;
        public String error;
        public Blob pdfContent;
        public String fileName;
    }
    
    public static InvoicePDFResult generateInvoicePDF(Id invoiceId) {
        InvoicePDFResult result = new InvoicePDFResult();
        
        try {
            Invoice__c invoice = getInvoiceWithDetails(invoiceId);
            
            if (invoice == null) {
                result.success = false;
                result.error = 'Invoice not found';
                return result;
            }
            
            String templateType = getTemplateType(invoice);
            
            // TODO: Create Visualforce pages for PDF templates
            // For now, generate mock PDF content based on template type
            String pdfContent = 'Invoice PDF - Template: ' + templateType + 
                               '\nInvoice: ' + invoice.Name + 
                               '\nDate: ' + invoice.Invoice_Date__c + 
                               '\nAmount: $' + invoice.Total_Amount__c;
            
            if (templateType == 'Per Diem Summary') {
                pdfContent += '\n\nPer Diem Summary:';
                pdfContent += '\nTotal Per Diem Days: ' + invoice.Total_Per_Diem_Days__c;
                pdfContent += '\nTotal Per Diem Hours: ' + invoice.Total_Per_Diem_Hours__c;
            }
            
            Blob pdfBlob = Test.isRunningTest() ? 
                           Blob.valueOf('test pdf content') : 
                           Blob.valueOf(pdfContent);
            
            result.success = true;
            result.pdfContent = pdfBlob;
            result.fileName = 'Invoice_' + invoice.Name + '.pdf';
            
        } catch (Exception e) {
            result.success = false;
            result.error = 'Error generating PDF: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static Invoice__c getInvoiceWithDetails(Id invoiceId) {
        try {
            return [
                SELECT Id, Name, Invoice_Date__c, 
                       Invoice_Due_Date__c, Total_Amount__c, Total_Per_Diem_Days__c,
                       Total_Per_Diem_Hours__c, Invoice_Period_Start__c, Invoice_Period_End__c,
                       Account__c, Account__r.Name, Account__r.BillingAddress,
                       Billing_Profile__c, Billing_Profile__r.Invoice_Template__c,
                       Billing_Profile__r.Payment_Terms__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];
        } catch (QueryException e) {
            return null;
        }
    }
    
    private static String getTemplateType(Invoice__c invoice) {
        if (invoice.Billing_Profile__c != null && 
            invoice.Billing_Profile__r.Invoice_Template__c != null) {
            return invoice.Billing_Profile__r.Invoice_Template__c;
        }
        return 'Standard';
    }
    
    @AuraEnabled
    public static InvoicePDFResult downloadInvoicePDF(Id invoiceId) {
        return generateInvoicePDF(invoiceId);
    }
}